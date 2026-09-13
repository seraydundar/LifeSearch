import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';

/// Thin wrapper around the `LocalItems` Drift table. This is the app's
/// actual source of truth for reads — `OfflineItemRepository` never reads
/// from Supabase directly, only through here.
class ItemLocalDataSource {
  ItemLocalDataSource(this._db);

  final AppDatabase _db;

  /// Runs [action] in one Drift transaction — for `OfflineItemRepository`
  /// to pair a local write with its `SyncQueueDataSource.enqueue()` call
  /// (P1-03, docs/requirements-audit-2026-09-13.md): those used to be two
  /// separate `await`s, so the app dying between them left a local-only
  /// mutation with no queue entry to ever push it — worse, the next
  /// `_pullRemote()` would then delete it outright, since a local id
  /// that's neither on the server nor in the pending queue looks exactly
  /// like "deleted elsewhere" (see `SyncService._pullRemote`'s
  /// `staleIds`). Any query issued through this same [AppDatabase]
  /// instance while [action] runs — including `SyncQueueDataSource`'s,
  /// which shares it — participates in the same transaction, so a
  /// failure partway through rolls back every write [action] made, not
  /// just this data source's own.
  Future<T> transaction<T>(Future<T> Function() action) => _db.transaction(action);

  Stream<List<LocalItem>> watchAll(String userId) {
    final query = _db.select(_db.localItems)
      ..where((t) => t.userId.equals(userId))
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    return query.watch();
  }

  /// Scoped to [userId] like every other read here (`watchAll`,
  /// `allIds`, ...) — **not** just `t.id.equals(itemId)` on its own
  /// (Faz 12, madde 3, denetim düzeltmesi — see docs/roadmap.md). A row
  /// from a *previous* account can still be sitting in this device's
  /// local cache (the app never wipes it on sign-out, only stops
  /// showing it in account-scoped lists — see Faz 10a's own documented
  /// limitation) — without this filter, a route that resolves an item
  /// straight from its id (a deep link, `ItemByIdLoader`, tapping a
  /// duplicate/related item) could hand a *different, currently
  /// signed-in* account someone else's cached note content.
  Future<LocalItem?> findById(String userId, String itemId) {
    return (_db.select(_db.localItems)
          ..where((t) => t.id.equals(itemId) & t.userId.equals(userId)))
        .getSingleOrNull();
  }

  /// Ids of every one of [userId]'s items still waiting on the AI
  /// pipeline — `SyncService` polls (see `_scheduleNextPollIfNeeded`) for
  /// as long as this is non-empty, so `processing`/`completed`/`failed`
  /// shows up without the user having to background/reopen the app or
  /// make an edit to trigger another sync.
  ///
  /// Returns the actual **ids**, not just whether any exist (Faz 12,
  /// madde 6, denetim düzeltmesi — see docs/roadmap.md): `SyncService`
  /// needs to tell "the same stuck job it's already been polling" apart
  /// from "a brand new item just started processing", so a long-stuck
  /// job can't permanently disable polling for everything that starts
  /// afterwards.
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
        // The content changed, so any existing embeddings are stale —
        // back to 'pending' until the AI pipeline re-processes it.
        processingStatus: const Value('pending'),
      ),
    );
  }

  /// Optimistic local-only update for `ItemRepository.retryProcessing()` —
  /// `processingStatus` itself is otherwise set exclusively by the backend
  /// pipeline (via a `_pullRemote()` sync), so this is deliberately
  /// overwritten on the next pull once the real status comes back.
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
}
