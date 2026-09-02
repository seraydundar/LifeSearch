import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/error/failure.dart';
import '../../domain/entities/item.dart';
import '../../domain/repositories/item_repository.dart';

class SupabaseItemRepository implements ItemRepository {
  SupabaseItemRepository(this._client);

  final SupabaseClient _client;
  static const _bucket = 'item-files';
  static const _uuid = Uuid();

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw const AuthFailure('Oturum bulunamadı.');
    return id;
  }

  Item _fromRow(Map<String, dynamic> row) => Item(
        id: row['id'] as String,
        type: ItemTypeX.fromDbValue(row['type'] as String),
        title: row['title'] as String?,
        description: row['description'] as String?,
        originalFilename: row['original_filename'] as String?,
        mimeType: row['mime_type'] as String?,
        storagePath: row['storage_path'] as String?,
        processingStatus: row['processing_status'] as String? ?? 'pending',
        favorite: row['favorite'] as bool? ?? false,
        createdAt: DateTime.parse(row['created_at'] as String),
      );

  @override
  Stream<List<Item>> watchItems() {
    return _client
        .from('items')
        .stream(primaryKey: ['id'])
        .eq('user_id', _userId)
        .order('created_at')
        .map((rows) => rows.reversed.map(_fromRow).toList());
  }

  @override
  Future<String> fetchNoteContent(String itemId) async {
    final row = await _client
        .from('item_contents')
        .select('raw_text')
        .eq('item_id', itemId)
        .maybeSingle();
    return (row?['raw_text'] as String?) ?? '';
  }

  @override
  Future<Item> createNote({required String title, required String content}) async {
    final id = _uuid.v4();
    try {
      await _client.from('items').insert({
        'id': id,
        'user_id': _userId,
        'type': ItemType.note.dbValue,
        'title': title,
        'processing_status': 'completed', // notes need no AI pipeline to be "ready"
      });
      try {
        await _client.from('item_contents').insert({'item_id': id, 'raw_text': content});
      } catch (_) {
        // Compensate: don't leave a note item with no content behind.
        await _client.from('items').delete().eq('id', id);
        rethrow;
      }
      final row = await _client.from('items').select().eq('id', id).single();
      return _fromRow(row);
    } on PostgrestException catch (e) {
      throw UnexpectedFailure('Not kaydedilemedi: ${e.message}');
    }
  }

  @override
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

  @override
  Future<Item> uploadFile({
    required String localFilePath,
    required String originalFilename,
    required String mimeType,
    required ItemType type,
  }) async {
    final id = _uuid.v4();
    final storagePath = '$_userId/$id/$originalFilename';

    try {
      await _client.storage.from(_bucket).upload(storagePath, File(localFilePath));
    } on StorageException catch (e) {
      throw UnexpectedFailure('Dosya yüklenemedi: ${e.message}');
    }

    try {
      await _client.from('items').insert({
        'id': id,
        'user_id': _userId,
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

    final row = await _client.from('items').select().eq('id', id).single();
    return _fromRow(row);
  }

  @override
  Future<String> getSignedUrl(String storagePath) {
    return _client.storage.from(_bucket).createSignedUrl(storagePath, 60 * 10);
  }

  @override
  Future<void> setFavorite(String itemId, bool favorite) async {
    try {
      await _client.from('items').update({'favorite': favorite}).eq('id', itemId);
    } on PostgrestException catch (e) {
      throw UnexpectedFailure('Güncellenemedi: ${e.message}');
    }
  }

  @override
  Future<void> deleteItem(Item item) async {
    if (item.storagePath != null) {
      await _client.storage.from(_bucket).remove([item.storagePath!]);
    }
    try {
      await _client.from('items').delete().eq('id', item.id);
    } on PostgrestException catch (e) {
      throw UnexpectedFailure('Silinemedi: ${e.message}');
    }
  }
}
