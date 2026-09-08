import 'package:flutter_test/flutter_test.dart';
import 'package:lifesearch/features/item/domain/entities/item.dart';
import 'package:lifesearch/features/settings/domain/storage_usage.dart';

Item _item({
  ItemType type = ItemType.pdf,
  int? fileSizeBytes,
}) {
  return Item(
    id: 'i',
    type: type,
    processingStatus: 'completed',
    favorite: false,
    createdAt: DateTime(2026, 1, 1),
    fileSizeBytes: fileSizeBytes,
  );
}

void main() {
  group('totalStorageBytes', () {
    test('sums fileSizeBytes across items', () {
      final items = [_item(fileSizeBytes: 100), _item(fileSizeBytes: 250)];

      expect(totalStorageBytes(items), 350);
    });

    test('treats a missing size as 0, not an error', () {
      final items = [_item(fileSizeBytes: 100), _item(fileSizeBytes: null)];

      expect(totalStorageBytes(items), 100);
    });

    test('an empty list is 0 bytes', () {
      expect(totalStorageBytes([]), 0);
    });
  });

  group('storageTotalIsIncomplete', () {
    test('true when a file-backed item has no recorded size', () {
      final items = [_item(type: ItemType.image, fileSizeBytes: null)];

      expect(storageTotalIsIncomplete(items), isTrue);
    });

    test('false when every file-backed item has a recorded size', () {
      final items = [_item(type: ItemType.image, fileSizeBytes: 100)];

      expect(storageTotalIsIncomplete(items), isFalse);
    });

    test('a note/link with no size does not count — nothing was ever uploaded', () {
      final items = [
        _item(type: ItemType.note, fileSizeBytes: null),
        _item(type: ItemType.url, fileSizeBytes: null),
      ];

      expect(storageTotalIsIncomplete(items), isFalse);
    });
  });

  group('formatBytes', () {
    test('bytes under 1 KB', () {
      expect(formatBytes(512), '512 B');
    });

    test('kilobytes', () {
      expect(formatBytes(1536), '1.5 KB');
    });

    test('megabytes', () {
      expect(formatBytes(1024 * 1024 * 2), '2.0 MB');
    });

    test('gigabytes', () {
      expect(formatBytes(1024 * 1024 * 1024 * 3), '3.00 GB');
    });
  });
}
