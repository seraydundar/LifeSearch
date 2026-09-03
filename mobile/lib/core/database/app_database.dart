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
  int get schemaVersion => 1;

  static QueryExecutor _openConnection() {
    // Picks the right native backend per platform and stores the file in
    // the app's documents directory — see the drift_flutter package.
    return driftDatabase(name: 'lifesearch');
  }
}
