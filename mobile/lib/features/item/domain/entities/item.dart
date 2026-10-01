import 'package:freezed_annotation/freezed_annotation.dart';

part 'item.freezed.dart';

/// Mirrors the `type` check constraint on the `items` table. Enum member
/// names are used verbatim as the DB values — see [ItemTypeX].
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
/// etc. A note's text body lives separately in `item_contents` (see
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
    // Set by the backend pipeline only. `null` means no duplicate found
    // (or dismissed already).
    String? duplicateOfItemId,
    double? duplicateSimilarity,
    @Default(false) bool duplicateDismissed,
    // EXIF-derived; `null` for screenshots, downloads, or location-off photos.
    double? latitude,
    double? longitude,
    DateTime? capturedAt,
    // `null` for notes/links and anything uploaded before this field existed.
    int? fileSizeBytes,
    // Hidden from Home/Library/Search unless revealed for the session
    // (see item_providers.dart's `privateItemsRevealedProvider`).
    @Default(false) bool private,
  }) = _Item;
}

extension ItemDisplayX on Item {
  /// The title shown wherever a single line is needed (list/grid tiles,
  /// sorting by name) — notes have a real `title`, uploaded files fall
  /// back to their filename, everything else to a placeholder.
  String get displayTitle => title ?? originalFilename ?? 'Untitled';
}
