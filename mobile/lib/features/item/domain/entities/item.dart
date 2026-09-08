import 'package:freezed_annotation/freezed_annotation.dart';

part 'item.freezed.dart';

/// Mirrors the `type` check constraint on the `items` table
/// (see infra/supabase/migrations/0001_init.sql). Enum member names are
/// used verbatim as the DB values — see [ItemTypeX].
enum ItemType { note, image, screenshot, pdf, audio, url, document }

extension ItemTypeX on ItemType {
  String get dbValue => name;

  static ItemType fromDbValue(String value) {
    return ItemType.values.firstWhere(
      (type) => type.name == value,
      orElse: () => ItemType.document,
    );
  }
}

/// A single piece of content the user saved — a note, an uploaded image/PDF,
/// etc. This is the row shape from the `items` table; the actual text body
/// of a note lives in `item_contents` and is fetched separately (see
/// `ItemRepository.fetchNoteContent`) since the list view never needs it.
@freezed
sealed class Item with _$Item {
  const factory Item({
    required String id,
    required ItemType type,
    String? title,
    String? description,
    String? originalFilename,
    String? mimeType,
    String? storagePath,
    String? sourceUrl,
    required String processingStatus,
    required bool favorite,
    required DateTime createdAt,
    // Duplicate Detection (requirements doc, section 46) — set by the
    // backend pipeline, never by the client. `null` duplicateOfItemId
    // means no candidate was found (or it's been dismissed already).
    String? duplicateOfItemId,
    double? duplicateSimilarity,
    @Default(false) bool duplicateDismissed,
    // EXIF-derived capture location/time (requirements doc, section
    // 8-12) — set by the backend pipeline from a photo's EXIF; `null`
    // for screenshots, downloaded images, or location-off photos.
    double? latitude,
    double? longitude,
    DateTime? capturedAt,
    // Set once at upload time — Settings' "Storage" tile sums these
    // (requirements doc, section 49-52). `null` for notes/links, and for
    // anything uploaded before this field existed.
    int? fileSizeBytes,
  }) = _Item;
}

extension ItemDisplayX on Item {
  /// The title shown wherever a single line is needed (list/grid tiles,
  /// sorting by name) — notes have a real `title`, uploaded files fall
  /// back to their filename, everything else to a placeholder.
  String get displayTitle => title ?? originalFilename ?? 'Untitled';
}
