import 'dart:async';

import 'package:lifesearch/features/collections/domain/entities/collection.dart';
import 'package:lifesearch/features/collections/domain/repositories/collection_repository.dart';
import 'package:lifesearch/features/item/domain/entities/item.dart';

/// In-memory `CollectionRepository` used by widget tests so they never
/// touch Supabase.
class FakeCollectionRepository implements CollectionRepository {
  FakeCollectionRepository({List<Collection> initialCollections = const []})
      : _collections = List.of(initialCollections);

  final List<Collection> _collections;
  final Map<String, Set<String>> _memberItemIds = {}; // collectionId -> itemIds
  final _collectionsController = StreamController<List<Collection>>.broadcast();
  final Map<String, List<Item>> itemsByCollection = {}; // test-populated fixture data

  void _emit() => _collectionsController.add(List.of(_collections));

  @override
  Stream<List<Collection>> watchCollections() {
    scheduleMicrotask(_emit);
    return _collectionsController.stream;
  }

  @override
  Future<Collection> createCollection(String name, {bool isSmart = false}) async {
    final collection = Collection(
      id: 'collection-${_collections.length}',
      name: name,
      isSmart: isSmart,
      createdAt: DateTime.now(),
    );
    _collections.add(collection);
    _emit();
    return collection;
  }

  @override
  Future<void> renameCollection(String id, String name) async {
    final index = _collections.indexWhere((c) => c.id == id);
    if (index == -1) return;
    _collections[index] = _collections[index].copyWith(name: name);
    _emit();
  }

  @override
  Future<void> deleteCollection(String id) async {
    _collections.removeWhere((c) => c.id == id);
    _emit();
  }

  @override
  Stream<List<Item>> watchCollectionItems(String collectionId) {
    return Stream.value(itemsByCollection[collectionId] ?? const []);
  }

  @override
  Future<void> addItemToCollection({required String collectionId, required String itemId}) async {
    _memberItemIds.putIfAbsent(collectionId, () => {}).add(itemId);
  }

  @override
  Future<void> removeItemFromCollection({
    required String collectionId,
    required String itemId,
  }) async {
    _memberItemIds[collectionId]?.remove(itemId);
  }

  @override
  Future<List<String>> collectionIdsForItem(String itemId) async {
    return _memberItemIds.entries
        .where((e) => e.value.contains(itemId))
        .map((e) => e.key)
        .toList();
  }

  /// (name, member item ids) for every collection created with
  /// `isSmart: true` — lets a test assert what an "Oluştur" tap actually
  /// produced without reaching into private state.
  List<(String, Set<String>)> get createdSmartCollections => _collections
      .where((c) => c.isSmart)
      .map((c) => (c.name, _memberItemIds[c.id] ?? const <String>{}))
      .toList();
}
