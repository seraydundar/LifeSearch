import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables/chat_messages.dart';
import 'tables/local_collection_items.dart';
import 'tables/local_collections.dart';
import 'tables/local_items.dart';
import 'tables/local_tags.dart';
import 'tables/recent_searches.dart';
import 'tables/sync_queue_entries.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    LocalItems,
    SyncQueueEntries,
    RecentSearches,
    LocalCollections,
    LocalCollectionItems,
    LocalTags,
    ChatMessages,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  AppDatabase.forTesting(super.connection);

  @override
  int get schemaVersion => 10;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          // v2 (Phase 8): URL items need somewhere to remember what they
          // point to — see infra/supabase/migrations/0005_url_items.sql
          // for the same column on the server side.
          if (from < 2) {
            await m.addColumn(localItems, localItems.sourceUrl);
          }
          // v3 (Faz 9 — Duplicate Detection): mirrors
          // infra/supabase/migrations/0007_duplicate_detection.sql.
          if (from < 3) {
            await m.addColumn(localItems, localItems.duplicateOfItemId);
            await m.addColumn(localItems, localItems.duplicateSimilarity);
            await m.addColumn(localItems, localItems.duplicateDismissed);
          }
          // v4 (Faz 9 sonrası — Konum/EXIF): mirrors the backend's
          // items.latitude/longitude/captured_at columns, populated from
          // a photo's EXIF at processing time.
          if (from < 4) {
            await m.addColumn(localItems, localItems.latitude);
            await m.addColumn(localItems, localItems.longitude);
            await m.addColumn(localItems, localItems.capturedAt);
          }
          // v5 (Settings — Storage): mirrors
          // infra/supabase/migrations/0010_item_file_size.sql.
          if (from < 5) {
            await m.addColumn(localItems, localItems.fileSizeBytes);
          }
          // v6 (Collections offline): mirrors
          // infra/supabase/migrations/0008_collections.sql — Collections
          // gets the same Drift + sync queue treatment every other
          // feature already had.
          if (from < 6) {
            await m.createTable(localCollections);
            await m.createTable(localCollectionItems);
          }
          // v7 (Faz 10a — hesap izolasyonu): SyncQueueEntries/RecentSearches
          // never carried a userId, so `pendingEntries()`/recent-search
          // queries read every account's rows on a shared device — a
          // still-queued item from a previous session could get pushed
          // under whichever account is signed in when the queue next
          // flushes. Backfilled from the item/collection each queue entry
          // actually targets (LocalItems/LocalCollections were already
          // correctly scoped) rather than guessing "whoever's signed in
          // now" — a queue entry outliving an account switch would get
          // the wrong owner under that guess. Anything whose target no
          // longer exists locally can't be safely attributed to anyone —
          // dropped rather than risking a write under the wrong account.
          // recent_searches has no such ownership trail to recover from,
          // so it's just cleared.
          if (from < 7) {
            await m.addColumn(syncQueueEntries, syncQueueEntries.userId);
            await m.addColumn(recentSearches, recentSearches.userId);
            await backfillSyncQueueOwnership();
            await delete(recentSearches).go();
          }
          // v8 (Faz 11 — item-level Privacy Mode): mirrors
          // infra/supabase/migrations/0014_item_private.sql.
          if (from < 8) {
            await m.addColumn(localItems, localItems.private);
          }
          // v9 (P2-07, docs/requirements-audit-2026-09-13.md — offline
          // search): tags and OCR/PDF/transcript/webpage text were never
          // synced to Drift, so `LocalSearchDataSource` couldn't match a
          // query against either. `extractedText` mirrors
          // `item_contents.raw_text`; `LocalTags` mirrors `item_tags`/`tags`.
          if (from < 9) {
            await m.addColumn(localItems, localItems.extractedText);
            await m.createTable(localTags);
          }
          // v10 (Faz 36 — Ask AI sohbeti kalıcılığı): mirrors nothing on
          // the backend — this conversation never left the device to
          // begin with, it just used to live in memory only.
          if (from < 10) {
            await m.createTable(chatMessages);
          }
        },
      );

  /// The v6->v7 backfill's actual logic, pulled out of the migration
  /// closure so it can be exercised directly in a test against a plain
  /// `forTesting` database (already on the current schema, with rows
  /// inserted at their post-`addColumn` default of `userId: ''`) instead
  /// of having to fabricate an actual old-schema sqlite file by hand.
  ///
  /// Recovers each queue entry's true owner from the item/collection it
  /// targets (`LocalItems`/`LocalCollections` were already correctly
  /// scoped — only the queue itself was missing this) rather than
  /// guessing "whoever's signed in now", which would mis-attribute any
  /// entry that outlived an account switch. An entry whose target no
  /// longer exists locally can't be safely attributed to anyone — it's
  /// dropped rather than risking a write under the wrong account.
  Future<void> backfillSyncQueueOwnership() async {
    final itemOwners = {
      for (final row in await select(localItems).get()) row.id: row.userId,
    };
    final collectionOwners = {
      for (final row in await select(localCollections).get()) row.id: row.userId,
    };
    const collectionOps = {
      'create_collection',
      'rename_collection',
      'delete_collection',
      'add_to_collection',
      'remove_from_collection',
    };

    for (final entry in await select(syncQueueEntries).get()) {
      final owners = collectionOps.contains(entry.operationType) ? collectionOwners : itemOwners;
      final owner = owners[entry.itemId];
      if (owner == null) {
        await (delete(syncQueueEntries)..where((t) => t.id.equals(entry.id))).go();
      } else {
        await (update(syncQueueEntries)..where((t) => t.id.equals(entry.id)))
            .write(SyncQueueEntriesCompanion(userId: Value(owner)));
      }
    }
  }

  static QueryExecutor _openConnection() {
    // Picks the right native backend per platform and stores the file in
    // the app's documents directory — see the drift_flutter package. On
    // web there's no filesystem to speak of, so drift runs sqlite
    // compiled to WASM inside a worker instead — `web/sqlite3.wasm` and
    // `web/drift_worker.dart.js` (Faz 11, madde 6c, see docs/roadmap.md)
    // downloaded from drift's own GitHub release matching this project's
    // exact pinned drift version (pubspec.lock's resolved version, not
    // just pubspec.yaml's `^` range — the two files must match the
    // drift version exactly or the worker protocol can silently
    // mismatch). `web:` is simply ignored on every non-web platform.
    return driftDatabase(
      name: 'lifesearch',
      web: DriftWebOptions(
        sqlite3Wasm: Uri.parse('sqlite3.wasm'),
        driftWorker: Uri.parse('drift_worker.dart.js'),
      ),
    );
  }
}
