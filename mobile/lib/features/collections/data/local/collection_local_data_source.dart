import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../item/data/local/local_item_x.dart';
import '../../../item/domain/entities/item.dart';

class CollectionLocalDataSource {
  CollectionLocalDataSource(this._db);

  final AppDatabase _db;

  /// Pairs a local write with its `SyncQueueDataSource.enqueue()` call atomically.
  Future<T> transaction<T>(Future<T> Function() action) => _db.transaction(action);

  Stream<List<LocalCollection>> watchAll(String userId) {
    final query = _db.select(_db.localCollections)
      ..where((t) => t.userId.equals(userId))
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    return query.watch();
  }

  Future<List<String>> allIds(String userId) async {
    final rows = await (_db.selectOnly(_db.localCollections)
          ..addColumns([_db.localCollections.id])
          ..where(_db.localCollections.userId.equals(userId)))
        .get();
    return rows.map((r) => r.read(_db.localCollections.id)!).toList();
  }

  Future<void> upsert(LocalCollectionsCompanion row) {
    return _db.into(_db.localCollections).insertOnConflictUpdate(row);
  }

  Future<void> updateName(String id, String name, {required String syncStatus}) {
    return (_db.update(_db.localCollections)..where((t) => t.id.equals(id))).write(
      LocalCollectionsCompanion(name: Value(name), syncStatus: Value(syncStatus)),
    );
  }

  Future<void> markSynced(String id) {
    return (_db.update(_db.localCollections)..where((t) => t.id.equals(id)))
        .write(const LocalCollectionsCompanion(syncStatus: Value('synced')));
  }

  Future<void> markFailed(String id) {
    return (_db.update(_db.localCollections)..where((t) => t.id.equals(id)))
        .write(const LocalCollectionsCompanion(syncStatus: Value('failed')));
  }

  /// Sqlite doesn't cascade deletes, so membership rows must be removed manually.
  Future<void> delete(String id) async {
    await (_db.delete(_db.localCollectionItems)..where((t) => t.collectionId.equals(id))).go();
    await (_db.delete(_db.localCollections)..where((t) => t.id.equals(id))).go();
  }

  Future<void> deleteMany(List<String> ids) async {
    await (_db.delete(_db.localCollectionItems)..where((t) => t.collectionId.isIn(ids))).go();
    await (_db.delete(_db.localCollections)..where((t) => t.id.isIn(ids))).go();
  }

  Future<void> addItem(
    String collectionId,
    String itemId, {
    required String syncStatus,
    DateTime? addedAt,
  }) {
    return _db.into(_db.localCollectionItems).insertOnConflictUpdate(
          LocalCollectionItemsCompanion.insert(
            collectionId: collectionId,
            itemId: itemId,
            addedAt: addedAt ?? DateTime.now(),
            syncStatus: Value(syncStatus),
          ),
        );
  }

  Future<void> removeItem(String collectionId, String itemId) {
    return (_db.delete(_db.localCollectionItems)
          ..where((t) => t.collectionId.equals(collectionId) & t.itemId.equals(itemId)))
        .go();
  }

  Future<void> markMembershipSynced(String collectionId, String itemId) {
    return (_db.update(_db.localCollectionItems)
          ..where((t) => t.collectionId.equals(collectionId) & t.itemId.equals(itemId)))
        .write(const LocalCollectionItemsCompanion(syncStatus: Value('synced')));
  }

  /// Joins against `LocalCollections` since `LocalCollectionItems` has no `userId`
  /// column; without it, sync could delete another account's cached memberships as "stale".
  Future<List<(String, String)>> allMemberships(String userId) async {
    final query = _db.select(_db.localCollectionItems).join([
      innerJoin(
        _db.localCollections,
        _db.localCollections.id.equalsExp(_db.localCollectionItems.collectionId),
      ),
    ])
      ..where(_db.localCollections.userId.equals(userId));

    final rows = await query.get();
    return rows.map((row) {
      final membership = row.readTable(_db.localCollectionItems);
      return (membership.collectionId, membership.itemId);
    }).toList();
  }

  /// Must filter by [userId] via join, not just `collectionId` — otherwise a stale
  /// collection id from a prior account could leak that account's cached items.
  /// Rows missing from `LocalItems` (pull not landed yet) are skipped, not crashed on.
  /// [includePrivate] should be the live `privateItemsRevealedProvider` value.
  Stream<List<Item>> watchItemsForCollection(
    String collectionId,
    String userId, {
    bool includePrivate = false,
  }) {
    final query = _db.select(_db.localCollectionItems).join([
      innerJoin(
        _db.localCollections,
        _db.localCollections.id.equalsExp(_db.localCollectionItems.collectionId),
      ),
      innerJoin(
        _db.localItems,
        _db.localItems.id.equalsExp(_db.localCollectionItems.itemId),
      ),
    ])
      ..where(_db.localCollectionItems.collectionId.equals(collectionId) &
          _db.localCollections.userId.equals(userId) &
          _db.localItems.userId.equals(userId))
      ..orderBy([OrderingTerm.desc(_db.localCollectionItems.addedAt)]);
    if (!includePrivate) {
      query.where(_db.localItems.private.equals(false));
    }

    return query
        .watch()
        .map((rows) => rows.map((row) => row.readTable(_db.localItems).toDomainItem()).toList());
  }

  Future<List<String>> collectionIdsForItem(String itemId) async {
    final rows = await (_db.selectOnly(_db.localCollectionItems)
          ..addColumns([_db.localCollectionItems.collectionId])
          ..where(_db.localCollectionItems.itemId.equals(itemId)))
        .get();
    return rows.map((r) => r.read(_db.localCollectionItems.collectionId)!).toList();
  }
}
