import '../../item/domain/entities/item.dart';

/// Sums Item.fileSizeBytes (recorded at upload time), not recomputed by listing files.
int totalStorageBytes(List<Item> items) {
  return items.fold(0, (sum, item) => sum + (item.fileSizeBytes ?? 0));
}

/// True when a file-backed item predates this field, making the total above a lower bound.
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
