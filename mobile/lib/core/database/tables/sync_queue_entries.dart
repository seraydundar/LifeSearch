import 'package:drift/drift.dart';

/// One pending write that a `SyncService` still needs to push to Supabase.
/// Created the moment a local mutation happens (online or offline) and
/// removed once it's confirmed on the server — see requirements doc,
/// section 32 "Sync Queue".
class SyncQueueEntries extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 'create_note' | 'update_note' | 'set_favorite' | 'delete_item' | 'upload_file'
  TextColumn get operationType => text()();

  /// The item this operation targets — same id used locally and remotely,
  /// so re-running a queued op after a partial failure is idempotent
  /// (an insert with the same id upserts rather than duplicating).
  TextColumn get itemId => text()();

  /// Operation-specific data as JSON (title/content, favorite flag, the
  /// local file path for an upload, ...).
  TextColumn get payload => text()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
}
