import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_database.dart';
import '../../domain/entities/item.dart';
import '../../domain/repositories/item_repository.dart';
import '../local/item_local_data_source.dart';
import '../local/sync_queue_data_source.dart';
import '../remote/remote_item_data_source.dart';
import '../sync/sync_service.dart';

/// Offline-first `ItemRepository`: every read comes from the local cache
/// (`ItemLocalDataSource`), every write lands there immediately and is
/// queued for `SyncService` to push to Supabase — the UI never blocks on
/// the network (requirements doc, section 38: Repository → {Local, Remote}).
class OfflineItemRepository implements ItemRepository {
  OfflineItemRepository({
    required ItemLocalDataSource local,
    required RemoteItemDataSource remote,
    required SyncQueueDataSource queue,
    required SyncService syncService,
  })  : _local = local,
        _remote = remote,
        _queue = queue,
        _syncService = syncService;

  final ItemLocalDataSource _local;
  final RemoteItemDataSource _remote;
  final SyncQueueDataSource _queue;
  final SyncService _syncService;
  static const _uuid = Uuid();

  String get _userId => _remote.userId;

  Item _toItem(LocalItem row) => Item(
        id: row.id,
        type: ItemTypeX.fromDbValue(row.type),
        title: row.title,
        description: row.description,
        originalFilename: row.originalFilename,
        mimeType: row.mimeType,
        storagePath: row.storagePath,
        sourceUrl: row.sourceUrl,
        processingStatus: row.processingStatus,
        favorite: row.favorite,
        createdAt: row.createdAt,
        duplicateOfItemId: row.duplicateOfItemId,
        duplicateSimilarity: row.duplicateSimilarity,
        duplicateDismissed: row.duplicateDismissed,
      );

  @override
  Stream<List<Item>> watchItems() {
    return _local.watchAll(_userId).map((rows) => rows.map(_toItem).toList());
  }

  @override
  Future<String> fetchNoteContent(String itemId) async {
    final local = await _local.findById(itemId);
    if (local?.noteContent != null) return local!.noteContent!;
    return _remote.fetchNoteContent(itemId); // cold-start fallback before the first sync
  }

  @override
  Future<List<String>> fetchTags(String itemId) => _remote.fetchTags(itemId);

  @override
  Future<Item?> findById(String itemId) async {
    final local = await _local.findById(itemId);
    return local == null ? null : _toItem(local);
  }

  @override
  Future<Item> createNote({required String title, required String content}) async {
    final id = _uuid.v4();
    final now = DateTime.now();

    await _local.upsert(LocalItemsCompanion.insert(
      id: id,
      userId: _userId,
      type: ItemType.note.dbValue,
      title: Value(title),
      // Chunked/embedded by the backend (Phase 4), same as PDFs — flips
      // to 'completed' once that job finishes, not immediately.
      processingStatus: const Value('pending'),
      createdAt: now,
      noteContent: Value(content),
      syncStatus: const Value('pending'),
    ));
    await _queue.enqueue(
      operationType: 'create_note',
      itemId: id,
      payload: {'title': title, 'content': content},
    );
    _syncService.syncSoon();

    return Item(
      id: id,
      type: ItemType.note,
      title: title,
      processingStatus: 'pending',
      favorite: false,
      createdAt: now,
    );
  }

  @override
  Future<void> updateNote({
    required String itemId,
    required String title,
    required String content,
  }) async {
    await _local.setNoteContent(itemId, title, content, syncStatus: 'pending');
    await _queue.enqueue(
      operationType: 'update_note',
      itemId: itemId,
      payload: {'title': title, 'content': content},
    );
    _syncService.syncSoon();
  }

  @override
  Future<Item> uploadFile({
    required String localFilePath,
    required String originalFilename,
    required String mimeType,
    required ItemType type,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now();

    // The path file_picker hands back can live in a cache dir the OS is
    // free to clear before we're back online — copy it into our own
    // documents dir so a queued upload survives that.
    final persistedPath = await _persistPickedFile(id, localFilePath, originalFilename);

    await _local.upsert(LocalItemsCompanion.insert(
      id: id,
      userId: _userId,
      type: type.dbValue,
      title: Value(originalFilename),
      originalFilename: Value(originalFilename),
      mimeType: Value(mimeType),
      processingStatus: const Value('pending'),
      createdAt: now,
      syncStatus: const Value('pending'),
    ));
    await _queue.enqueue(
      operationType: 'upload_file',
      itemId: id,
      payload: {
        'localFilePath': persistedPath,
        'originalFilename': originalFilename,
        'mimeType': mimeType,
        'type': type.dbValue,
      },
    );
    _syncService.syncSoon();

    return Item(
      id: id,
      type: type,
      title: originalFilename,
      originalFilename: originalFilename,
      mimeType: mimeType,
      processingStatus: 'pending',
      favorite: false,
      createdAt: now,
    );
  }

  @override
  Future<Item> createUrlItem({required String url}) async {
    final id = _uuid.v4();
    final now = DateTime.now();

    await _local.upsert(LocalItemsCompanion.insert(
      id: id,
      userId: _userId,
      type: ItemType.url.dbValue,
      title: Value(url),
      sourceUrl: Value(url),
      processingStatus: const Value('pending'),
      createdAt: now,
      syncStatus: const Value('pending'),
    ));
    await _queue.enqueue(
      operationType: 'create_url',
      itemId: id,
      payload: {'url': url},
    );
    _syncService.syncSoon();

    return Item(
      id: id,
      type: ItemType.url,
      title: url,
      sourceUrl: url,
      processingStatus: 'pending',
      favorite: false,
      createdAt: now,
    );
  }

  Future<String> _persistPickedFile(String id, String sourcePath, String originalFilename) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final targetDir = Directory('${docsDir.path}/pending_uploads');
    await targetDir.create(recursive: true);
    final targetPath = '${targetDir.path}/$id-$originalFilename';
    await File(sourcePath).copy(targetPath);
    return targetPath;
  }

  @override
  Future<String> getSignedUrl(String storagePath) {
    // Not cached offline yet — viewing a file's actual content still needs
    // a connection. Local metadata (title, type, status) works offline.
    return _remote.getSignedUrl(storagePath);
  }

  @override
  Future<void> setFavorite(String itemId, bool favorite) async {
    await _local.setFavorite(itemId, favorite, syncStatus: 'pending');
    await _queue.enqueue(
      operationType: 'set_favorite',
      itemId: itemId,
      payload: {'favorite': favorite},
    );
    _syncService.syncSoon();
  }

  @override
  Future<void> dismissDuplicate(String itemId) async {
    await _local.setDuplicateDismissed(itemId, syncStatus: 'pending');
    await _queue.enqueue(operationType: 'dismiss_duplicate', itemId: itemId, payload: const {});
    _syncService.syncSoon();
  }

  @override
  Future<void> deleteItem(Item item) async {
    await _local.delete(item.id);
    await _queue.enqueue(
      operationType: 'delete_item',
      itemId: item.id,
      payload: {'storagePath': item.storagePath},
    );
    _syncService.syncSoon();
  }
}
