import '../../../item/domain/entities/item.dart';
import '../entities/collection.dart';

/// Contract the presentation layer codes against — Supabase-direct for
/// now (no offline cache yet), the same way `ItemRepository` started in
/// Phase 2 before Phase 3 added Drift underneath it.
abstract interface class CollectionRepository {
  Stream<List<Collection>> watchCollections();

  Future<Collection> createCollection(String name);

  Future<void> renameCollection(String id, String name);

  Future<void> deleteCollection(String id);

  /// The items currently in a collection, newest-added first.
  Stream<List<Item>> watchCollectionItems(String collectionId);

  Future<void> addItemToCollection({required String collectionId, required String itemId});

  Future<void> removeItemFromCollection({required String collectionId, required String itemId});

  /// Ids of every collection the given item already belongs to — powers
  /// the checkbox state in the "Add to Collection" sheet on item detail.
  Future<List<String>> collectionIdsForItem(String itemId);
}
