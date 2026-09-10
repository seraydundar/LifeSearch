import 'package:drift/drift.dart';

/// One pending write that a `SyncService` still needs to push to Supabase.
/// Created the moment a local mutation happens (online or offline) and
/// removed once it's confirmed on the server — see requirements doc,
/// section 32 "Sync Queue".
class SyncQueueEntries extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Whose operation this is. Without this, `pendingEntries()` couldn't
  /// tell one account's queued writes apart from another's on a shared
  /// device — a still-queued item from a previous session could get
  /// pushed to Supabase under whichever account happens to be signed in
  /// when the queue next flushes (requirements doc, rule 14: "Kullanıcının
  /// verilerini başka kullanıcıların sorgularında kullanma"). Defaults to
  /// `''` only so the v6->v7 migration's `ALTER TABLE ADD COLUMN` has
  /// something to backfill from — every real insert always supplies it.
  TextColumn get userId => text().withDefault(const Constant(''))();

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
