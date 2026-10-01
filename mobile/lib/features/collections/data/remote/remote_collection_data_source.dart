import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/network/paginated_fetch.dart';
import '../../domain/entities/collection.dart';

/// Writes take an explicit `id` from the caller instead of letting Postgres
/// generate one, so a replayed queued sync op stays idempotent.
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

  Future<List<Map<String, dynamic>>> fetchAllRows() {
    return fetchAllPages((from, to) {
      return _client
          .from('collections')
          .select()
          .eq('user_id', userId)
          .order('created_at')
          .order('id')
          .range(from, to);
    });
  }

  /// `collection_items` has no `user_id`, so the caller must pass ids from `fetchAllRows()`.
  Future<List<Map<String, dynamic>>> fetchAllItemRows(List<String> collectionIds) async {
    if (collectionIds.isEmpty) return const [];
    return fetchAllPages((from, to) {
      return _client
          .from('collection_items')
          .select()
          .inFilter('collection_id', collectionIds)
          .order('collection_id')
          .order('item_id')
          .range(from, to);
    });
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
