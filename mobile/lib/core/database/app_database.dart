import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables/local_items.dart';
import 'tables/recent_searches.dart';
import 'tables/sync_queue_entries.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [LocalItems, SyncQueueEntries, RecentSearches])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  AppDatabase.forTesting(super.connection);

  @override
  int get schemaVersion => 2;

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
        },
      );

  static QueryExecutor _openConnection() {
    // Picks the right native backend per platform and stores the file in
    // the app's documents directory — see the drift_flutter package.
    return driftDatabase(name: 'lifesearch');
  }
}
