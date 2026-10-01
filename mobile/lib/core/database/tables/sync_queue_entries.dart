import 'package:drift/drift.dart';

/// One pending write a `SyncService` still needs to push to Supabase; removed once confirmed on the server.
class SyncQueueEntries extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Scopes queued writes per account on a shared device. Defaults to '' only for the v6->v7 backfill.
  TextColumn get userId => text().withDefault(const Constant(''))();

  /// 'create_note' | 'update_note' | 'set_favorite' | 'delete_item' | 'upload_file'
  TextColumn get operationType => text()();

  /// Target item id, reused across retries so a re-run upserts instead of duplicating.
  TextColumn get itemId => text()();

  /// Operation-specific data as JSON (title/content, favorite flag, the local file path for an upload, ...).
  TextColumn get payload => text()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
}
