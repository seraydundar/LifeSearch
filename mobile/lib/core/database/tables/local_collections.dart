import 'package:drift/drift.dart';

/// Local cache of the `collections` table; UI reads only from here, `SyncService` reconciles with Supabase.
class LocalCollections extends Table {
  // Client-generated UUID, not the server default — lets a queued create retry idempotently.
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get name => text()();
  BoolColumn get isSmart => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();

  /// 'synced' | 'pending' | 'failed'; pending/failed rows have a matching SyncQueueEntries row.
  TextColumn get syncStatus => text().withDefault(const Constant('synced'))();

  @override
  Set<Column> get primaryKey => {id};
}
