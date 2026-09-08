import 'package:lifesearch/features/item/domain/entities/item.dart';
import 'package:lifesearch/features/item/domain/repositories/item_repository.dart';

/// In-memory `ItemRepository` used by widget tests so they never touch
/// Supabase.
class FakeItemRepository implements ItemRepository {
  FakeItemRepository({List<Item> initialItems = const []})
      : _items = List.of(initialItems);

  final List<Item> _items;

  @override
  Stream<List<Item>> watchItems() => Stream.value(List.of(_items));

  @override
  Future<String> fetchNoteContent(String itemId) async => 'fake content';

  @override
  Future<Item?> findById(String itemId) async {
    for (final item in _items) {
      if (item.id == itemId) return item;
    }
    return null;
  }

  Map<String, List<String>> tagsByItemId = {};

  @override
  Future<List<String>> fetchTags(String itemId) async => tagsByItemId[itemId] ?? const [];

  @override
  Future<Item> createNote({required String title, required String content}) async {
    final item = Item(
      id: 'note-${_items.length}',
      type: ItemType.note,
      title: title,
      processingStatus: 'completed',
      favorite: false,
      createdAt: DateTime.now(),
    );
    _items.insert(0, item);
    return item;
  }

  @override
  Future<void> updateNote({
    required String itemId,
    required String title,
    required String content,
  }) async {}

  @override
  Future<Item> uploadFile({
    required String localFilePath,
    required String originalFilename,
    required String mimeType,
    required ItemType type,
  }) async {
    final item = Item(
      id: 'file-${_items.length}',
      type: type,
      title: originalFilename,
      originalFilename: originalFilename,
      mimeType: mimeType,
      storagePath: 'fake/$originalFilename',
      processingStatus: 'pending',
      favorite: false,
      createdAt: DateTime.now(),
    );
    _items.insert(0, item);
    return item;
  }

  @override
  Future<Item> createUrlItem({required String url}) async {
    final item = Item(
      id: 'url-${_items.length}',
      type: ItemType.url,
      title: url,
      sourceUrl: url,
      processingStatus: 'pending',
      favorite: false,
      createdAt: DateTime.now(),
    );
    _items.insert(0, item);
    return item;
  }

  @override
  Future<String> getSignedUrl(String storagePath) async => 'https://example.test/$storagePath';

  @override
  Future<void> setFavorite(String itemId, bool favorite) async {}

  @override
  Future<void> dismissDuplicate(String itemId) async {}

  @override
  Future<void> deleteItem(Item item) async {
    _items.removeWhere((i) => i.id == item.id);
  }
}
