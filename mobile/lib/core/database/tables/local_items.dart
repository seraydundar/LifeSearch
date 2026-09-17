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

  /// Set by the backend's duplicate-detection step (requirements doc,
  /// section 46) when a near-identical item already exists — see
  /// infra/supabase/migrations/0007_duplicate_detection.sql. Only ever
  /// flags; the user decides whether to dismiss it.
  TextColumn get duplicateOfItemId => text().nullable()();
  RealColumn get duplicateSimilarity => real().nullable()();
  BoolColumn get duplicateDismissed => boolean().withDefault(const Constant(false))();

  /// EXIF-derived capture location/time (requirements doc, section
  /// 8-12) — only ever set for photos with GPS EXIF; `null` for
  /// everything else (screenshots, downloaded images, location off).
  /// See backend/app/services/exif_service.py.
  RealColumn get latitude => real().nullable()();
  RealColumn get longitude => real().nullable()();
  DateTimeColumn get capturedAt => dateTime().nullable()();

  /// Recorded once at upload time (the client already knows the file's
  /// size before uploading) — Settings' "Storage" tile sums these rather
  /// than recursively listing every item's Storage folder. `null` for
  /// notes/links (nothing uploaded) and for anything uploaded before
  /// this column existed.
  IntColumn get fileSizeBytes => integer().nullable()();

  /// Item-level Privacy Mode (requirements doc; see docs/roadmap.md,
  /// Faz 11, madde 2) — hidden from Home/Library/Search
  /// (`item_providers.dart`'s `itemsProvider`) unless the user passes a
  /// biometric/PIN check to reveal private items for the session,
  /// independent of whether the whole-app lock (Settings' "Privacy"
  /// switch) is even turned on.
  BoolColumn get private => boolean().withDefault(const Constant(false))();

  /// Mirrors `item_contents.raw_text` (infra/supabase/migrations/0001_init.sql) —
  /// the pipeline's one canonical "full text" per item: OCR text for a
  /// scanned PDF/screenshot, the extracted body for a PDF/DOCX/TXT, an
  /// audio transcript, or a scraped webpage's article text (see
  /// backend/app/services/processing_pipeline.py). For images it's the
  /// vision description and OCR text concatenated. Synced read-only by
  /// `SyncService._pullRemote` — never written locally, so there's no
  /// pending/queued-edit case to worry about the way `noteContent` has.
  /// Added for P2-07 (docs/requirements-audit-2026-09-13.md): before this,
  /// `LocalSearchDataSource` had no copy of this text at all, so a query
  /// only matching a scanned page's OCR text, a PDF's body or a link's
  /// article text found nothing offline.
  TextColumn get extractedText => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
