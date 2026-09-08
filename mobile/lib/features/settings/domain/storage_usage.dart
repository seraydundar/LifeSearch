import '../../item/domain/entities/item.dart';

/// Settings' "Storage" tile (requirements doc, section 49-52) — sums
/// `Item.fileSizeBytes`, recorded once at upload time (see
/// `OfflineItemRepository.uploadFile`) rather than recomputed by
/// recursively listing every item's Storage folder.
int totalStorageBytes(List<Item> items) {
  return items.fold(0, (sum, item) => sum + (item.fileSizeBytes ?? 0));
}

/// True when at least one file-backed item (not a note/link) has no
/// recorded size — i.e. it was uploaded before this field existed, so
/// the total above is a lower bound, not the real number.
bool storageTotalIsIncomplete(List<Item> items) {
  const fileTypes = {
    ItemType.image,
    ItemType.screenshot,
    ItemType.pdf,
    ItemType.audio,
    ItemType.document,
  };
  return items.any((item) => fileTypes.contains(item.type) && item.fileSizeBytes == null);
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
  final gb = mb / 1024;
  return '${gb.toStringAsFixed(2)} GB';
}
