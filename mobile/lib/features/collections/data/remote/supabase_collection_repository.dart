import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/error/failure.dart';
import '../../../item/data/remote/remote_item_data_source.dart';
import '../../../item/domain/entities/item.dart';
import '../../domain/entities/collection.dart';
import '../../domain/repositories/collection_repository.dart';

/// Talks to Supabase directly, no local cache — see `CollectionRepository`
/// for why. Reuses `RemoteItemDataSource.rowToItem` for `items` rows
/// instead of re-implementing that mapping here.
class SupabaseCollectionRepository implements CollectionRepository {
  SupabaseCollectionRepository(this._client, this._itemDataSource);

  final SupabaseClient _client;
  final RemoteItemDataSource _itemDataSource;

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw const AuthFailure('Oturum bulunamadı.');
    return id;
  }

  Collection _toCollection(Map<String, dynamic> row) => Collection(
        id: row['id'] as String,
        name: row['name'] as String,
        isSmart: row['is_smart'] as bool? ?? false,
        createdAt: DateTime.parse(row['created_at'] as String),
      );

  @override
  Stream<List<Collection>> watchCollections() {
    return _client
        .from('collections')
        .stream(primaryKey: ['id'])
        .eq('user_id', _userId)
        .order('created_at')
        .map((rows) => rows.map(_toCollection).toList());
  }

  @override
  Future<Collection> createCollection(String name) async {
    try {
      final row = await _client
          .from('collections')
          .insert({'user_id': _userId, 'name': name})
          .select()
          .single();
      return _toCollection(row);
    } on PostgrestException catch (e) {
      throw UnexpectedFailure('Koleksiyon oluşturulamadı: ${e.message}');
    }
  }

  @override
  Future<void> renameCollection(String id, String name) async {
    try {
      await _client.from('collections').update({'name': name}).eq('id', id);
    } on PostgrestException catch (e) {
      throw UnexpectedFailure('Koleksiyon güncellenemedi: ${e.message}');
    }
  }

  @override
  Future<void> deleteCollection(String id) async {
    try {
      await _client.from('collections').delete().eq('id', id);
    } on PostgrestException catch (e) {
      throw UnexpectedFailure('Koleksiyon silinemedi: ${e.message}');
    }
  }

  @override
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

  @override
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

  @override
  Future<List<String>> collectionIdsForItem(String itemId) async {
    final rows =
        await _client.from('collection_items').select('collection_id').eq('item_id', itemId);
    return rows.map((r) => r['collection_id'] as String).toList();
  }

  @override
  Stream<List<Item>> watchCollectionItems(String collectionId) {
    // `collection_items` carries no item columns of its own, and
    // Supabase's realtime `.stream()` doesn't support joins — stream the
    // junction rows and re-fetch the matching `items` rows on every
    // change instead of trying to merge two live streams.
    return _client
        .from('collection_items')
        .stream(primaryKey: ['collection_id', 'item_id'])
        .eq('collection_id', collectionId)
        .asyncMap((rows) async {
      final itemIds = rows.map((r) => r['item_id'] as String).toList();
      if (itemIds.isEmpty) return <Item>[];
      final itemRows = await _client.from('items').select().inFilter('id', itemIds);
      final items = itemRows.map(_itemDataSource.rowToItem).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return items;
    });
  }
}
