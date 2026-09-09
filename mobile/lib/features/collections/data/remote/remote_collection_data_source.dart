import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/error/failure.dart';
import '../../domain/entities/collection.dart';

/// Talks to Supabase directly. Like `RemoteItemDataSource`, every write
/// takes an explicit `id`/pair supplied by the caller rather than letting
/// Postgres generate one — that's what makes replaying a queued sync
/// operation idempotent.
///
/// Nothing outside `features/collections/data` should import this
/// directly — screens/controllers depend on `CollectionRepository`.
class RemoteCollectionDataSource {
  RemoteCollectionDataSource(this._client);

  final SupabaseClient _client;

  String get userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw const AuthFailure('Oturum bulunamadı.');
    return id;
  }

  Collection rowToCollection(Map<String, dynamic> row) => Collection(
        id: row['id'] as String,
        name: row['name'] as String,
        isSmart: row['is_smart'] as bool? ?? false,
        createdAt: DateTime.parse(row['created_at'] as String),
      );

  /// One-shot snapshot of every collection the user has — used by
  /// `SyncService` to reconcile the local cache, not by the UI directly.
  Future<List<Map<String, dynamic>>> fetchAllRows() {
    return _client.from('collections').select().eq('user_id', userId).order('created_at');
  }

  /// Every (collection_id, item_id) membership row across the given
  /// collections — `collection_items` carries no `user_id` of its own, so
  /// the caller passes the ids `fetchAllRows()` just returned rather than
  /// this filtering by user itself.
  Future<List<Map<String, dynamic>>> fetchAllItemRows(List<String> collectionIds) async {
    if (collectionIds.isEmpty) return const [];
    return _client.from('collection_items').select().inFilter('collection_id', collectionIds);
  }

  Future<void> createCollection({
    required String id,
    required String name,
    required bool isSmart,
  }) async {
    try {
      await _client.from('collections').upsert({
        'id': id,
        'user_id': userId,
        'name': name,
        'is_smart': isSmart,
      });
    } on PostgrestException catch (e) {
      throw UnexpectedFailure('Koleksiyon oluşturulamadı: ${e.message}');
    }
  }

  Future<void> renameCollection(String id, String name) async {
    try {
      await _client.from('collections').update({'name': name}).eq('id', id);
    } on PostgrestException catch (e) {
      throw UnexpectedFailure('Koleksiyon güncellenemedi: ${e.message}');
    }
  }

  Future<void> deleteCollection(String id) async {
    try {
      await _client.from('collections').delete().eq('id', id);
    } on PostgrestException catch (e) {
      throw UnexpectedFailure('Koleksiyon silinemedi: ${e.message}');
    }
  }

  Future<void> addItemToCollection({required String collectionId, required String itemId}) async {
    try {
      await _client.from('collection_items').upsert(
        {'collection_id': collectionId, 'item_id': itemId},
        onConflict: 'collection_id,item_id',
      );
    } on PostgrestException catch (e) {
      throw UnexpectedFailure('Eklenemedi: ${e.message}');
    }
  }

  Future<void> removeItemFromCollection({
    required String collectionId,
    required String itemId,
  }) async {
    try {
      await _client
          .from('collection_items')
          .delete()
          .eq('collection_id', collectionId)
          .eq('item_id', itemId);
    } on PostgrestException catch (e) {
      throw UnexpectedFailure('Kaldırılamadı: ${e.message}');
    }
  }
}
