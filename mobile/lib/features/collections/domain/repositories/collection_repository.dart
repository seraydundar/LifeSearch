import '../../../item/domain/entities/item.dart';
import '../entities/collection.dart';

abstract interface class CollectionRepository {
  Stream<List<Collection>> watchCollections();

  /// `isSmart: true` marks a collection accepted from an AI suggestion; informational only for now.
  Future<Collection> createCollection(String name, {bool isSmart = false});

  Future<void> renameCollection(String id, String name);

  Future<void> deleteCollection(String id);

  /// Scoped to the signed-in user internally, so a stale [collectionId] from a
  /// previous account never resolves. [includePrivate] should be the live
  /// `privateItemsRevealedProvider` value.
  Stream<List<Item>> watchCollectionItems(String collectionId, {bool includePrivate = false});

  Future<void> addItemToCollection({required String collectionId, required String itemId});

  Future<void> removeItemFromCollection({required String collectionId, required String itemId});

  Future<List<String>> collectionIdsForItem(String itemId);
}
