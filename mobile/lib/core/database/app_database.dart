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
          if (from < 2) {
            await m.addColumn(localItems, localItems.sourceUrl);
          }
          if (from < 3) {
            await m.addColumn(localItems, localItems.duplicateOfItemId);
            await m.addColumn(localItems, localItems.duplicateSimilarity);
            await m.addColumn(localItems, localItems.duplicateDismissed);
          }
          if (from < 4) {
            await m.addColumn(localItems, localItems.latitude);
            await m.addColumn(localItems, localItems.longitude);
            await m.addColumn(localItems, localItems.capturedAt);
          }
          if (from < 5) {
            await m.addColumn(localItems, localItems.fileSizeBytes);
          }
          if (from < 6) {
            await m.createTable(localCollections);
            await m.createTable(localCollectionItems);
          }
          // Backfills userId from each entry's target item/collection rather than guessing
          // "whoever's signed in now"; entries with no surviving target are dropped, not misattributed.
          if (from < 7) {
            await m.addColumn(syncQueueEntries, syncQueueEntries.userId);
            await m.addColumn(recentSearches, recentSearches.userId);
            await backfillSyncQueueOwnership();
            await delete(recentSearches).go();
          }
          if (from < 8) {
            await m.addColumn(localItems, localItems.private);
          }
          if (from < 9) {
            await m.addColumn(localItems, localItems.extractedText);
            await m.createTable(localTags);
          }
          if (from < 10) {
            await m.createTable(chatMessages);
          }
        },
      );

  /// Pulled out of the migration closure so the v6->v7 backfill can be tested directly against a
  /// `forTesting` database instead of fabricating an old-schema sqlite file. Recovers each queue
  /// entry's owner from its target item/collection; entries with no surviving target are dropped.
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
    // web/sqlite3.wasm and web/drift_worker.dart.js must match pubspec.lock's exact drift
    // version (not just pubspec.yaml's `^` range) or the worker protocol can silently mismatch.
    return driftDatabase(
      name: 'lifesearch',
      web: DriftWebOptions(
        sqlite3Wasm: Uri.parse('sqlite3.wasm'),
        driftWorker: Uri.parse('drift_worker.dart.js'),
      ),
    );
  }
}
