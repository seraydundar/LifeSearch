import 'package:drift/drift.dart';

/// Local cache of the `collections` table (see
/// infra/supabase/migrations/0008_collections.sql) — same offline-first
/// pattern as `LocalItems`: the UI reads only from here, a background
/// `SyncService` keeps it reconciled with Supabase.
class LocalCollections extends Table {
  // Client-generated UUID (not the server's `gen_random_uuid()` default —
  // the client must own the id for a queued create to be idempotently
  // retryable, same reasoning as LocalItems.id).
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get name => text()();
  BoolColumn get isSmart => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();

  /// 'synced' | 'pending' | 'failed' — pending/failed rows have a matching
  /// SyncQueueEntries row driving the retry.
  TextColumn get syncStatus => text().withDefault(const Constant('synced'))();

  @override
  Set<Column> get primaryKey => {id};
}
