import 'package:drift/drift.dart';

/// Local cache of the `items` table (see infra/supabase/migrations/0001_init.sql).
/// This — not a live Supabase query — is what the UI actually reads from;
/// a background `SyncService` keeps it reconciled with the server.
class LocalItems extends Table {
  TextColumn get id => text()(); // same UUID as the Supabase row, client-generated
  TextColumn get userId => text()();
  TextColumn get type => text()();
  TextColumn get title => text().nullable()();
  TextColumn get description => text().nullable()();
  TextColumn get originalFilename => text().nullable()();
  TextColumn get mimeType => text().nullable()();
  TextColumn get storagePath => text().nullable()();

  /// Only set for `type == url` — what the item actually points to.
  TextColumn get sourceUrl => text().nullable()();
  TextColumn get processingStatus => text().withDefault(const Constant('pending'))();
  BoolColumn get favorite => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();

  /// Only populated for notes — the app's local-first source for note
  /// bodies, so editing/reading a note never needs the network.
  TextColumn get noteContent => text().nullable()();

  /// 'synced' | 'pending' | 'failed' — pending/failed rows have a matching
  /// SyncQueueEntries row driving the retry.
  TextColumn get syncStatus => text().withDefault(const Constant('synced'))();

  @override
  Set<Column> get primaryKey => {id};
}
