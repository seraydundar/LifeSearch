import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/network/paginated_fetch.dart';
import '../../domain/entities/extracted_entity.dart';
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
        duplicateOfItemId: row['duplicate_of_item_id'] as String?,
        duplicateSimilarity: (row['duplicate_similarity'] as num?)?.toDouble(),
        duplicateDismissed: row['duplicate_dismissed'] as bool? ?? false,
        latitude: (row['latitude'] as num?)?.toDouble(),
        longitude: (row['longitude'] as num?)?.toDouble(),
        capturedAt: row['captured_at'] == null
            ? null
            : DateTime.parse(row['captured_at'] as String),
        fileSizeBytes: (row['file_size_bytes'] as num?)?.toInt(),
        private: row['private'] as bool? ?? false,
      );

  /// One-shot snapshot of every item the user has — used by `SyncService`
  /// to reconcile the local cache, not by the UI directly.
  ///
  /// Paginated (Faz 12, madde 9, denetim düzeltmesi — see
  /// docs/roadmap.md): a plain `.select()` with no `.range()` silently
  /// truncates past PostgREST's configured row cap instead of erroring.
  /// `SyncService` treats "not in this response" as "deleted on the
  /// server" — for an archive larger than one page, everything past the
  /// cap used to look deleted and get wiped from the local cache on the
  /// very next sync. `.order('id')` as a tiebreaker after `created_at`
  /// keeps paging deterministic even when many rows share the exact same
  /// timestamp (e.g. a bulk import) — without it, a tied ordering could
  /// vary between page requests and skip or repeat rows across pages.
  Future<List<Map<String, dynamic>>> fetchAllRows() {
    return fetchAllPages((from, to) {
      return _client
          .from('items')
          .select()
          .eq('user_id', userId)
          .order('created_at')
          .order('id')
          .range(from, to);
    });
  }

  /// A single row by id, or `null` if it doesn't exist (or isn't this
  /// user's — RLS scopes this the same as [fetchAllRows]) — used by
  /// `OfflineItemRepository.findById()`'s remote fallback (P2-09,
  /// docs/requirements-audit-2026-09-13.md) for an item this device
  /// hasn't synced yet (a search/RAG/related-item result, or a deep
  /// link, for something created on another device).
  Future<Item?> fetchById(String itemId) async {
    final rows = await _client.from('items').select().eq('id', itemId).eq('user_id', userId);
    return rows.isEmpty ? null : rowToItem(rows.first);
  }

  Future<String> fetchNoteContent(String itemId) async {
    final row = await _client
        .from('item_contents')
        .select('raw_text')
        .eq('item_id', itemId)
        .maybeSingle();
    return (row?['raw_text'] as String?) ?? '';
  }

  /// Joins through `item_tags` to `tags` — nested select syntax, RLS
  /// applies to both tables so this only ever returns the caller's own.
  Future<List<String>> fetchTags(String itemId) async {
    final rows = await _client.from('item_tags').select('tags(name)').eq('item_id', itemId);
    return rows.map((row) => (row['tags'] as Map<String, dynamic>)['name'] as String).toList();
  }

  /// Every tag *occurrence* across the signed-in user's whole archive —
  /// one entry per (item, tag) association, not deduplicated (Analytics'
  /// "most common tags" counts the duplicates, see
  /// `analytics.dart`'s `topTags`). Same join shape as `fetchTags`, just
  /// without the `item_id` filter — RLS (see `item_tags_owner` in
  /// infra/supabase/migrations/0001_init.sql) already scopes this to the
  /// caller's own rows on its own.
  Future<List<String>> fetchAllTagNames() async {
    final rows = await _client.from('item_tags').select('tags(name)');
    return rows.map((row) => (row['tags'] as Map<String, dynamic>)['name'] as String).toList();
  }

  /// Same join-through-the-junction-table shape as `fetchTags`.
  Future<List<ExtractedEntity>> fetchEntities(String itemId) async {
    final rows =
        await _client.from('item_entities').select('entities(name, type)').eq('item_id', itemId);
    return rows.map((row) {
      final entity = row['entities'] as Map<String, dynamic>;
      return ExtractedEntity(
        name: entity['name'] as String,
        type: EntityTypeX.fromDbValue(entity['type'] as String),
      );
    }).toList();
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
    int? fileSizeBytes,
  }) async {
    // Pinned once — not re-read after the storage upload's `await` below
    // (P1-03, docs/requirements-audit-2026-09-13.md): the storage path
    // and the item row's `user_id` must agree even if the live session
    // actually changes mid-upload, otherwise the file ends up stored
    // under one account while the row that points at it claims another.
    // If the session really did change, RLS's `auth.uid() = user_id`
    // rejects the upsert below outright — a clean failure (caught same
    // as any other) instead of a silent cross-account write.
    final ownerId = userId;
    final storagePath = '$ownerId/$id/$originalFilename';

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
        'user_id': ownerId,
        'type': type.dbValue,
        'title': originalFilename,
        'original_filename': originalFilename,
        'mime_type': mimeType,
        'storage_path': storagePath,
        'file_size_bytes': fileSizeBytes,
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

  Future<void> setPrivate(String itemId, bool private) async {
    try {
      await _client.from('items').update({'private': private}).eq('id', itemId);
    } on PostgrestException catch (e) {
      throw UnexpectedFailure('Güncellenemedi: ${e.message}');
    }
  }

  Future<void> dismissDuplicate(String itemId) async {
    try {
      await _client.from('items').update({'duplicate_dismissed': true}).eq('id', itemId);
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
