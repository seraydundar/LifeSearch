import 'dart:async';

import 'package:lifesearch/features/item/domain/entities/extracted_entity.dart';
import 'package:lifesearch/features/item/domain/entities/item.dart';
import 'package:lifesearch/features/item/domain/repositories/item_repository.dart';

/// In-memory `ItemRepository` used by widget/integration tests so they
/// never touch Supabase.
///
/// `watchItems()` is genuinely reactive — matching the real
/// `OfflineItemRepository`, which is backed by a live Drift stream — so a
/// screen that's already watching it sees a `createNote`/`uploadFile`/etc.
/// immediately, without needing a manual refresh. A plain one-shot
/// `Stream.value(...)` (the original version of this fake) can't do that:
/// it closes right after its single emission, so any mutation made after
/// a screen started watching would silently never show up.
class FakeItemRepository implements ItemRepository {
  FakeItemRepository({List<Item> initialItems = const []}) : _items = List.of(initialItems);

  final List<Item> _items;
  final _controller = StreamController<List<Item>>.broadcast();

  void _notify() => _controller.add(List.of(_items));

  @override
  Stream<List<Item>> watchItems() async* {
    yield List.of(_items);
    yield* _controller.stream;
  }

  /// Stands in for a background `SyncService` pull picking up a change
  /// made somewhere else — the backend finishing AI processing, a second
  /// device's edit, etc. — as opposed to every other mutation method
  /// here, which stands in for *this* screen's own write. Replaces the
  /// item by id (a no-op if it isn't present) and notifies watchers, same
  /// as every other mutation.
  void updateItem(Item updated) {
    final index = _items.indexWhere((i) => i.id == updated.id);
    if (index == -1) return;
    _items[index] = updated;
    _notify();
  }

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

  List<String> allTagNames = [];

  @override
  Future<List<String>> fetchAllTagNames() async => allTagNames;

  Map<String, List<ExtractedEntity>> entitiesByItemId = {};

  @override
  Future<List<ExtractedEntity>> fetchEntities(String itemId) async =>
      entitiesByItemId[itemId] ?? const [];

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
    _notify();
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
    _notify();
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
    _notify();
    return item;
  }

  @override
  Future<String> getSignedUrl(String storagePath) async => 'https://example.test/$storagePath';

  @override
  Future<void> setFavorite(String itemId, bool favorite) async {
    final index = _items.indexWhere((i) => i.id == itemId);
    if (index == -1) return;
    _items[index] = _items[index].copyWith(favorite: favorite);
    _notify();
  }

  @override
  Future<void> setPrivate(String itemId, bool private) async {
    final index = _items.indexWhere((i) => i.id == itemId);
    if (index == -1) return;
    _items[index] = _items[index].copyWith(private: private);
    _notify();
  }

  @override
  Future<void> dismissDuplicate(String itemId) async {}

  @override
  Future<void> deleteItem(Item item) async {
    _items.removeWhere((i) => i.id == item.id);
    _notify();
  }

  int retryProcessingCallCount = 0;

  @override
  Future<void> retryProcessing(String itemId) async {
    retryProcessingCallCount++;
    final index = _items.indexWhere((i) => i.id == itemId);
    if (index == -1) return;
    _items[index] = _items[index].copyWith(processingStatus: 'pending');
    _notify();
  }
}
