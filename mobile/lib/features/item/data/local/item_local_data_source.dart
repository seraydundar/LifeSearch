import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';

/// Source of truth for reads — `OfflineItemRepository` never reads from
/// Supabase directly, only through here.
class ItemLocalDataSource {
  ItemLocalDataSource(this._db);

  final AppDatabase _db;

  /// Runs [action] atomically so a local write and its queued sync entry
  /// can't be split by a crash — a write with no queue entry looks
  /// "deleted elsewhere" to the next pull and gets wiped.
  Future<T> transaction<T>(Future<T> Function() action) => _db.transaction(action);

  Stream<List<LocalItem>> watchAll(String userId) {
    final query = _db.select(_db.localItems)
      ..where((t) => t.userId.equals(userId))
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    return query.watch();
  }

  /// Must filter by [userId], not just the id: a previous account's rows
  /// stay cached on sign-out, so an id-only lookup could leak another
  /// account's cached content to whoever is signed in now.
  Future<LocalItem?> findById(String userId, String itemId) {
    return (_db.select(_db.localItems)
          ..where((t) => t.id.equals(itemId) & t.userId.equals(userId)))
        .getSingleOrNull();
  }

  /// Returns ids, not just a count: `SyncService` polls while this is
  /// non-empty, and needs to tell an already-tracked stuck job apart from
  /// a newly started one so one stuck job can't block polling for others.
  Future<Set<String>> unfinishedProcessingIds(String userId) async {
    final rows = await (_db.selectOnly(_db.localItems)
          ..addColumns([_db.localItems.id])
          ..where(_db.localItems.userId.equals(userId) &
              _db.localItems.processingStatus.isIn(const ['pending', 'processing'])))
        .get();
    return rows.map((r) => r.read(_db.localItems.id)!).toSet();
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

  Future<void> setPrivate(String itemId, bool private, {required String syncStatus}) {
    return (_db.update(_db.localItems)..where((t) => t.id.equals(itemId))).write(
      LocalItemsCompanion(private: Value(private), syncStatus: Value(syncStatus)),
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
        // Content changed, so stale embeddings need re-processing.
        processingStatus: const Value('pending'),
      ),
    );
  }

  /// Optimistic only — overwritten on the next pull once the backend's
  /// real status comes back.
  Future<void> setProcessingStatus(String itemId, String status) {
    return (_db.update(_db.localItems)..where((t) => t.id.equals(itemId)))
        .write(LocalItemsCompanion(processingStatus: Value(status)));
  }

  Future<void> setDuplicateDismissed(String itemId, {required String syncStatus}) {
    return (_db.update(_db.localItems)..where((t) => t.id.equals(itemId))).write(
      LocalItemsCompanion(duplicateDismissed: const Value(true), syncStatus: Value(syncStatus)),
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

  /// Wholesale replace, not a diff: tags carry no pending/queued state to
  /// clobber. [itemIds] scopes the delete since `LocalTags` has no
  /// `userId` column, and is assumed non-empty by the caller.
  Future<void> replaceTags(
    List<String> itemIds,
    List<({String itemId, String name})> tagRows,
  ) {
    return _db.batch((batch) {
      batch.deleteWhere(_db.localTags, (t) => t.itemId.isIn(itemIds));
      batch.insertAll(
        _db.localTags,
        [for (final row in tagRows) LocalTagsCompanion.insert(itemId: row.itemId, name: row.name)],
        mode: InsertMode.insertOrIgnore,
      );
    });
  }
}
