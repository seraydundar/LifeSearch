import 'dart:io';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/network/paginated_fetch.dart';
import '../../domain/entities/extracted_entity.dart';
import '../../domain/entities/item.dart';

/// Talks to Supabase directly. Writes take a caller-supplied `id` so
/// replaying a queued sync op upserts instead of duplicating. Import only
/// within `features/item/data` — screens/controllers use `ItemRepository`.
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

  /// Every item, or only those changed since [since] (`updated_at`).
  /// Paginated: an unranged `.select()` silently truncates past
  /// PostgREST's row cap, which `SyncService` would otherwise mistake for
  /// server-side deletions. `.order('id')` breaks ties after
  /// `created_at` so paging stays deterministic for same-timestamp rows.
  /// [since]-filtered results can't distinguish "unchanged" from
  /// "deleted" — see [fetchAllIds] for that.
  Future<List<Map<String, dynamic>>> fetchAllRows({DateTime? since}) {
    return fetchAllPages((from, to) {
      final query = _client.from('items').select().eq('user_id', userId);
      final filtered =
          since == null ? query : query.gte('updated_at', since.toUtc().toIso8601String());
      return filtered.order('created_at').order('id').range(from, to);
    });
  }

  /// Id-only, for `SyncService` to detect server-side deletions during an
  /// incremental sync — cheaper than a full [fetchAllRows].
  Future<Set<String>> fetchAllIds() async {
    final rows = await fetchAllPages((from, to) {
      return _client.from('items').select('id').eq('user_id', userId).order('id').range(from, to);
    });
    return {for (final row in rows) row['id'] as String};
  }

  /// `null` if the row doesn't exist or isn't this user's (RLS-scoped).
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

  Future<List<String>> fetchTags(String itemId) async {
    final rows = await _client.from('item_tags').select('tags(name)').eq('item_id', itemId);
    return rows.map((row) => (row['tags'] as Map<String, dynamic>)['name'] as String).toList();
  }

  /// One entry per (item, tag) association, not deduplicated — analytics'
  /// "most common tags" needs the duplicate counts.
  Future<List<String>> fetchAllTagNames() async {
    final rows = await _client.from('item_tags').select('tags(name)');
    return rows.map((row) => (row['tags'] as Map<String, dynamic>)['name'] as String).toList();
  }

  /// For `SyncService`'s offline cache, paginated like [fetchAllRows].
  /// [itemIds] narrows to an incremental sync's changed ids; left `null`
  /// on a first sync, since filtering by every id risks an oversized URL.
  Future<List<Map<String, dynamic>>> fetchAllItemTagRows({List<String>? itemIds}) {
    return fetchAllPages((from, to) {
      final query = _client.from('item_tags').select('item_id, tags(name)');
      final filtered = itemIds == null ? query : query.inFilter('item_id', itemIds);
      return filtered.order('item_id').order('tag_id').range(from, to);
    });
  }

  /// [itemIds]: same incremental-sync scoping as [fetchAllItemTagRows].
  Future<List<Map<String, dynamic>>> fetchAllItemContentRows({List<String>? itemIds}) {
    return fetchAllPages((from, to) {
      final query = _client.from('item_contents').select('item_id, raw_text');
      final filtered = itemIds == null ? query : query.inFilter('item_id', itemIds);
      return filtered.order('item_id').range(from, to);
    });
  }

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
        'processing_status': 'pending',
      });
      try {
        await _client.from('item_contents').upsert(
          {'item_id': id, 'raw_text': content},
          onConflict: 'item_id',
        );
      } catch (_) {
        // Roll back rather than leave a note with no content.
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
    // Pinned once so storage path and row's user_id agree even if the
    // session changes mid-upload; RLS rejects the upsert otherwise.
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
        'processing_status': 'pending',
      });
    } catch (e) {
      await _client.storage.from(_bucket).remove([storagePath]); // don't leave an orphan file
      throw UnexpectedFailure('İçerik kaydedilemedi. Lütfen tekrar dene.');
    }
  }

  /// Same two-step contract as [uploadFile], for callers with only bytes
  /// in memory (e.g. `file_picker` on web). Not queued for offline retry —
  /// there's no persistent local file to re-read after a web restart, so
  /// failures surface to the caller immediately.
  Future<void> uploadFileBytes({
    required String id,
    required Uint8List bytes,
    required String originalFilename,
    required String mimeType,
    required ItemType type,
    int? fileSizeBytes,
  }) async {
    final ownerId = userId;
    final storagePath = '$ownerId/$id/$originalFilename';

    try {
      await _client.storage.from(_bucket).uploadBinary(
            storagePath,
            bytes,
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
        'processing_status': 'pending',
      });
    } catch (e) {
      await _client.storage.from(_bucket).remove([storagePath]);
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
