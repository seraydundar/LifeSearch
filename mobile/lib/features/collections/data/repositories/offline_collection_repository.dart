import 'package:drift/drift.dart' show Value;
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/sync/sync_service.dart';
import '../../../item/data/local/sync_queue_data_source.dart';
import '../../../item/domain/entities/item.dart';
import '../../domain/entities/collection.dart';
import '../../domain/repositories/collection_repository.dart';
import '../local/collection_local_data_source.dart';
import '../remote/remote_collection_data_source.dart';

/// Offline-first `CollectionRepository`: every read comes from the local
/// cache, every write lands there immediately and is queued for
/// `SyncService` to push to Supabase — same pattern as
/// `OfflineItemRepository`, which this superseded
/// `SupabaseCollectionRepository`'s "no offline cache yet" note.
class OfflineCollectionRepository implements CollectionRepository {
  OfflineCollectionRepository({
    required CollectionLocalDataSource local,
    required RemoteCollectionDataSource remote,
    required SyncQueueDataSource queue,
    required SyncService syncService,
  })  : _local = local,
        _remote = remote,
        _queue = queue,
        _syncService = syncService;

  final CollectionLocalDataSource _local;
  final RemoteCollectionDataSource _remote;
  final SyncQueueDataSource _queue;
  final SyncService _syncService;
  static const _uuid = Uuid();

  String get _userId => _remote.userId;

  Collection _toCollection(LocalCollection row) => Collection(
        id: row.id,
        name: row.name,
        isSmart: row.isSmart,
        createdAt: row.createdAt,
      );

  @override
  Stream<List<Collection>> watchCollections() {
    return _local.watchAll(_userId).map((rows) => rows.map(_toCollection).toList());
  }

  @override
  Future<Collection> createCollection(String name, {bool isSmart = false}) async {
    final id = _uuid.v4();
    final now = DateTime.now();

    await _local.upsert(LocalCollectionsCompanion.insert(
      id: id,
      userId: _userId,
      name: name,
      isSmart: Value(isSmart),
      createdAt: now,
      syncStatus: const Value('pending'),
    ));
    await _queue.enqueue(
      operationType: 'create_collection',
      itemId: id,
      payload: {'name': name, 'isSmart': isSmart},
    );
    _syncService.syncSoon();

    return Collection(id: id, name: name, isSmart: isSmart, createdAt: now);
  }

  @override
  Future<void> renameCollection(String id, String name) async {
    await _local.updateName(id, name, syncStatus: 'pending');
    await _queue.enqueue(
      operationType: 'rename_collection',
      itemId: id,
      payload: {'name': name},
    );
    _syncService.syncSoon();
  }

  @override
  Future<void> deleteCollection(String id) async {
    await _local.delete(id);
    await _queue.enqueue(operationType: 'delete_collection', itemId: id, payload: const {});
    _syncService.syncSoon();
  }

  @override
  Stream<List<Item>> watchCollectionItems(String collectionId) {
    return _local.watchItemsForCollection(collectionId);
  }

  @override
  Future<void> addItemToCollection({required String collectionId, required String itemId}) async {
    await _local.addItem(collectionId, itemId, syncStatus: 'pending');
    await _queue.enqueue(
      operationType: 'add_to_collection',
      itemId: collectionId,
      payload: {'itemId': itemId},
    );
    _syncService.syncSoon();
  }

  @override
  Future<void> removeItemFromCollection({
    required String collectionId,
    required String itemId,
  }) async {
    await _local.removeItem(collectionId, itemId);
    await _queue.enqueue(
      operationType: 'remove_from_collection',
      itemId: collectionId,
      payload: {'itemId': itemId},
    );
    _syncService.syncSoon();
  }

  @override
  Future<List<String>> collectionIdsForItem(String itemId) {
    return _local.collectionIdsForItem(itemId);
  }
}
