import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/error/failure.dart';
import '../../domain/entities/item.dart';

/// Talks to Supabase directly. Every write takes an explicit `id` supplied
/// by the caller (`OfflineItemRepository`) rather than generating its own —
/// that's what makes replaying a queued sync operation idempotent: pushing
/// the same `id` twice upserts instead of duplicating (requirements doc,
/// rules 16-17).
///
/// Nothing outside `features/item/data` should import this directly —
/// screens/controllers depend on `ItemRepository`.
class RemoteItemDataSource {
  RemoteItemDataSource(this._client);

  final SupabaseClient _client;
  static const _bucket = 'item-files';

  String get userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw const AuthFailure('Oturum bulunamadı.');
    return id;
  }

  Item rowToItem(Map<String, dynamic> row) => Item(
        id: row['id'] as String,
        type: ItemTypeX.fromDbValue(row['type'] as String),
        title: row['title'] as String?,
        description: row['description'] as String?,
        originalFilename: row['original_filename'] as String?,
        mimeType: row['mime_type'] as String?,
        storagePath: row['storage_path'] as String?,
        sourceUrl: row['source_url'] as String?,
        processingStatus: row['processing_status'] as String? ?? 'pending',
        favorite: row['favorite'] as bool? ?? false,
        createdAt: DateTime.parse(row['created_at'] as String),
      );

  /// One-shot snapshot of every item the user has — used by `SyncService`
  /// to reconcile the local cache, not by the UI directly.
  Future<List<Map<String, dynamic>>> fetchAllRows() {
    return _client.from('items').select().eq('user_id', userId).order('created_at');
  }

  Future<String> fetchNoteContent(String itemId) async {
    final row = await _client
        .from('item_contents')
        .select('raw_text')
        .eq('item_id', itemId)
        .maybeSingle();
    return (row?['raw_text'] as String?) ?? '';
  }

  Future<void> createNote({
    required String id,
    required String title,
    required String content,
  }) async {
    try {
      await _client.from('items').upsert({
        'id': id,
        'user_id': userId,
        'type': ItemType.note.dbValue,
        'title': title,
        // Chunked/embedded by the backend (Phase 4), same as PDFs.
        'processing_status': 'pending',
      });
      try {
        await _client.from('item_contents').upsert(
          {'item_id': id, 'raw_text': content},
          onConflict: 'item_id',
        );
      } catch (_) {
        // Compensate: don't leave a note item with no content behind. Only
        // safe because `id` is caller-owned — retrying the whole op later
        // just recreates both rows from scratch.
        await _client.from('items').delete().eq('id', id);
        rethrow;
      }
    } on PostgrestException catch (e) {
      throw UnexpectedFailure('Not kaydedilemedi: ${e.message}');
    }
  }

  Future<void> updateNote({
    required String itemId,
    required String title,
    required String content,
  }) async {
    try {
      await _client.from('items').update({'title': title}).eq('id', itemId);
      await _client.from('item_contents').update({'raw_text': content}).eq('item_id', itemId);
    } on PostgrestException catch (e) {
      throw UnexpectedFailure('Not güncellenemedi: ${e.message}');
    }
  }

  Future<void> uploadFile({
    required String id,
    required String localFilePath,
    required String originalFilename,
    required String mimeType,
    required ItemType type,
  }) async {
    final storagePath = '$userId/$id/$originalFilename';

    try {
      await _client.storage.from(_bucket).upload(
            storagePath,
            File(localFilePath),
            fileOptions: const FileOptions(upsert: true),
          );
    } on StorageException catch (e) {
      throw UnexpectedFailure('Dosya yüklenemedi: ${e.message}');
    }

    try {
      await _client.from('items').upsert({
        'id': id,
        'user_id': userId,
        'type': type.dbValue,
        'title': originalFilename,
        'original_filename': originalFilename,
        'mime_type': mimeType,
        'storage_path': storagePath,
        // No worker consumes this yet — Phase 4 wires OCR/chunking/embedding.
        'processing_status': 'pending',
      });
    } catch (e) {
      await _client.storage.from(_bucket).remove([storagePath]); // don't leave an orphan file
      throw UnexpectedFailure('İçerik kaydedilemedi. Lütfen tekrar dene.');
    }
  }

  Future<void> createUrlItem({
    required String id,
    required String url,
    String? title,
  }) async {
    try {
      await _client.from('items').upsert({
        'id': id,
        'user_id': userId,
        'type': ItemType.url.dbValue,
        'title': title ?? url,
        'source_url': url,
        'processing_status': 'pending',
      });
    } on PostgrestException catch (e) {
      throw UnexpectedFailure('Link kaydedilemedi: ${e.message}');
    }
  }

  Future<String> getSignedUrl(String storagePath) {
    return _client.storage.from(_bucket).createSignedUrl(storagePath, 60 * 10);
  }

  Future<void> setFavorite(String itemId, bool favorite) async {
    try {
      await _client.from('items').update({'favorite': favorite}).eq('id', itemId);
    } on PostgrestException catch (e) {
      throw UnexpectedFailure('Güncellenemedi: ${e.message}');
    }
  }

  Future<void> deleteItem({required String itemId, String? storagePath}) async {
    if (storagePath != null) {
      await _client.storage.from(_bucket).remove([storagePath]);
    }
    try {
      await _client.from('items').delete().eq('id', itemId);
    } on PostgrestException catch (e) {
      throw UnexpectedFailure('Silinemedi: ${e.message}');
    }
  }
}
