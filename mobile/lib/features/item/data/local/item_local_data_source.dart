import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';

/// Thin wrapper around the `LocalItems` Drift table. This is the app's
/// actual source of truth for reads — `OfflineItemRepository` never reads
/// from Supabase directly, only through here.
class ItemLocalDataSource {
  ItemLocalDataSource(this._db);

  final AppDatabase _db;

  Stream<List<LocalItem>> watchAll(String userId) {
    final query = _db.select(_db.localItems)
      ..where((t) => t.userId.equals(userId))
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    return query.watch();
  }

  Future<LocalItem?> findById(String itemId) {
    return (_db.select(_db.localItems)..where((t) => t.id.equals(itemId))).getSingleOrNull();
  }

  Future<List<String>> allIds(String userId) async {
    final rows = await (_db.selectOnly(_db.localItems)
          ..addColumns([_db.localItems.id])
          ..where(_db.localItems.userId.equals(userId)))
        .get();
    return rows.map((r) => r.read(_db.localItems.id)!).toList();
  }

  Future<void> upsert(LocalItemsCompanion row) {
    return _db.into(_db.localItems).insertOnConflictUpdate(row);
  }

  Future<void> setFavorite(String itemId, bool favorite, {required String syncStatus}) {
    return (_db.update(_db.localItems)..where((t) => t.id.equals(itemId))).write(
      LocalItemsCompanion(favorite: Value(favorite), syncStatus: Value(syncStatus)),
    );
  }

  Future<void> setNoteContent(
    String itemId,
    String title,
    String content, {
    required String syncStatus,
  }) {
    return (_db.update(_db.localItems)..where((t) => t.id.equals(itemId))).write(
      LocalItemsCompanion(
        title: Value(title),
        noteContent: Value(content),
        syncStatus: Value(syncStatus),
        // The content changed, so any existing embeddings are stale —
        // back to 'pending' until the AI pipeline re-processes it.
        processingStatus: const Value('pending'),
      ),
    );
  }

  Future<void> markSynced(String itemId) {
    return (_db.update(_db.localItems)..where((t) => t.id.equals(itemId)))
        .write(const LocalItemsCompanion(syncStatus: Value('synced')));
  }

  Future<void> markFailed(String itemId) {
    return (_db.update(_db.localItems)..where((t) => t.id.equals(itemId)))
        .write(const LocalItemsCompanion(syncStatus: Value('failed')));
  }

  Future<void> delete(String itemId) {
    return (_db.delete(_db.localItems)..where((t) => t.id.equals(itemId))).go();
  }

  Future<void> deleteMany(List<String> ids) {
    return (_db.delete(_db.localItems)..where((t) => t.id.isIn(ids))).go();
  }
}
