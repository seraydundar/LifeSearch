import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../item/data/local/local_item_x.dart';
import '../../../item/domain/entities/item.dart';

/// Thin wrapper around the `LocalCollections`/`LocalCollectionItems` Drift
/// tables — same role as `ItemLocalDataSource` for items. This is what
/// `OfflineCollectionRepository` actually reads from; `SyncService` keeps
/// it reconciled with Supabase.
class CollectionLocalDataSource {
  CollectionLocalDataSource(this._db);

  final AppDatabase _db;

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

  /// Deletes the collection and every membership row that pointed at it —
  /// sqlite doesn't cascade this automatically the way Postgres does.
  Future<void> delete(String id) async {
    await (_db.delete(_db.localCollectionItems)..where((t) => t.collectionId.equals(id))).go();
    await (_db.delete(_db.localCollections)..where((t) => t.id.equals(id))).go();
  }

  Future<void> deleteMany(List<String> ids) async {
    await (_db.delete(_db.localCollectionItems)..where((t) => t.collectionId.isIn(ids))).go();
    await (_db.delete(_db.localCollections)..where((t) => t.id.isIn(ids))).go();
  }

  // ---- membership (LocalCollectionItems) ----

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

  /// Every (collectionId, itemId) pair currently cached locally — used by
  /// `SyncService` to reconcile against the server's membership rows.
  Future<List<(String, String)>> allMemberships() async {
    final rows = await _db.select(_db.localCollectionItems).get();
    return rows.map((r) => (r.collectionId, r.itemId)).toList();
  }

  /// The items in a collection, joined against `LocalItems`, newest-added
  /// first — matches `CollectionRepository.watchCollectionItems`'s
  /// contract. An item can briefly be missing from `LocalItems` (its own
  /// pull hasn't landed yet) — that row is skipped rather than crashing.
  Stream<List<Item>> watchItemsForCollection(String collectionId) {
    final query = _db.select(_db.localCollectionItems).join([
      innerJoin(
        _db.localItems,
        _db.localItems.id.equalsExp(_db.localCollectionItems.itemId),
      ),
    ])
      ..where(_db.localCollectionItems.collectionId.equals(collectionId))
      ..orderBy([OrderingTerm.desc(_db.localCollectionItems.addedAt)]);

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
