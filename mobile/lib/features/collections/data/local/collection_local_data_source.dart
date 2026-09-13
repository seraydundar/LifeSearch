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

  /// Same contract as `ItemLocalDataSource.transaction` (P1-03,
  /// docs/requirements-audit-2026-09-13.md) — pairs a local
  /// collection/membership write with its `SyncQueueDataSource.enqueue()`
  /// call in `OfflineCollectionRepository` atomically, since both data
  /// sources share this same [AppDatabase] instance.
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

  /// Every (collectionId, itemId) pair currently cached locally for
  /// [userId] — used by `SyncService` to reconcile against the server's
  /// membership rows. Scoped via an inner join against `LocalCollections`
  /// (Faz 12, madde 4, denetim düzeltmesi — see docs/roadmap.md):
  /// `LocalCollectionItems` itself carries no `userId` column of its own,
  /// and without this join, syncing as one account would see — and then
  /// *delete*, as "stale" — a different, previously signed-in account's
  /// still-cached membership rows, since they'd never appear in this
  /// account's own server-fetched membership set.
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

  /// The items in a collection, joined against `LocalItems`, newest-added
  /// first — matches `CollectionRepository.watchCollectionItems`'s
  /// contract. An item can briefly be missing from `LocalItems` (its own
  /// pull hasn't landed yet) — that row is skipped rather than crashing.
  ///
  /// **P1-01** (docs/requirements-audit-2026-09-13.md): this used to
  /// filter by `collectionId` alone, with no check that the collection —
  /// or the items in it — actually belong to [userId]. A stale
  /// `collectionId` still sitting in route state after an account switch
  /// (or simply a shared device's cache not yet purged) was a second,
  /// unfiltered way to reach another account's cached items, alongside
  /// whatever `itemsProvider`'s per-user filtering already caught.
  /// Requires an inner join against `LocalCollections`, not just a
  /// `where` on the membership row — `LocalCollectionItems` itself
  /// carries no `userId` column (see `allMemberships`'s docstring).
  ///
  /// [includePrivate] mirrors `SearchRepository.search`'s contract
  /// (P1-02): pass the live `privateItemsRevealedProvider` value so a
  /// private item is excluded from a collection's detail list the same
  /// way it already is from Home/Library.
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
