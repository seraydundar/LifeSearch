import 'package:drift/drift.dart';

/// Local cache of the `items` table; this is what the UI reads from, `SyncService` reconciles it with the server.
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

  /// Only populated for notes — local-first source, so editing/reading a note never needs the network.
  TextColumn get noteContent => text().nullable()();

  /// 'synced' | 'pending' | 'failed'; pending/failed rows have a matching SyncQueueEntries row.
  TextColumn get syncStatus => text().withDefault(const Constant('synced'))();

  /// Set by the backend's duplicate-detection step; only ever flags — the user decides whether to dismiss.
  TextColumn get duplicateOfItemId => text().nullable()();
  RealColumn get duplicateSimilarity => real().nullable()();
  BoolColumn get duplicateDismissed => boolean().withDefault(const Constant(false))();

  /// EXIF capture location/time; null unless the photo had GPS EXIF.
  RealColumn get latitude => real().nullable()();
  RealColumn get longitude => real().nullable()();
  DateTimeColumn get capturedAt => dateTime().nullable()();

  /// Recorded at upload time; summed by Settings' Storage tile. Null for notes/links and pre-existing items.
  IntColumn get fileSizeBytes => integer().nullable()();

  /// Item-level Privacy Mode; hidden from Home/Library/Search unless the user reveals private items for
  /// the session, independent of whether the whole-app lock is on.
  BoolColumn get private => boolean().withDefault(const Constant(false))();

  /// Mirrors `item_contents.raw_text` (OCR/PDF/transcript/webpage text); synced read-only, never written locally.
  TextColumn get extractedText => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
