import 'package:flutter_test/flutter_test.dart';
import 'package:lifesearch/features/analytics/domain/analytics.dart';
import 'package:lifesearch/features/item/domain/entities/item.dart';

Item _item({
  required String id,
  ItemType type = ItemType.note,
  bool favorite = false,
  bool private = false,
  required DateTime createdAt,
}) {
  return Item(
    id: id,
    type: type,
    processingStatus: 'completed',
    favorite: favorite,
    private: private,
    createdAt: createdAt,
  );
}

void main() {
  final items = [
    _item(id: '1', type: ItemType.note, favorite: true, createdAt: DateTime(2026, 1, 1)),
    _item(id: '2', type: ItemType.note, createdAt: DateTime(2026, 1, 2)),
    _item(id: '3', type: ItemType.pdf, private: true, createdAt: DateTime(2026, 2, 1)),
    _item(id: '4', type: ItemType.image, createdAt: DateTime(2026, 2, 5)),
  ];

  test('totalItemCount counts every item', () {
    expect(totalItemCount(items), 4);
    expect(totalItemCount([]), 0);
  });

  test('favoriteCount counts only favorited items', () {
    expect(favoriteCount(items), 1);
  });

  test('privateCount counts only private items', () {
    expect(privateCount(items), 1);
  });

  test('countsByType groups by ItemType', () {
    final counts = countsByType(items);

    expect(counts[ItemType.note], 2);
    expect(counts[ItemType.pdf], 1);
    expect(counts[ItemType.image], 1);
    expect(counts.containsKey(ItemType.audio), isFalse); // never zero-filled
  });

  test('countsByType on an empty list is an empty map, not a crash', () {
    expect(countsByType([]), isEmpty);
  });

  group('itemsPerMonth', () {
    test('returns exactly `months` entries, zero-filled for gaps', () {
      final result = itemsPerMonth(items, months: 3, now: DateTime(2026, 3, 15));

      expect(result, hasLength(3));
      expect(result.map((m) => (m.month.year, m.month.month)), [
        (2026, 1),
        (2026, 2),
        (2026, 3),
      ]);
      expect(result[0].count, 2); // Jan: item 1, 2
      expect(result[1].count, 2); // Feb: item 3, 4
      expect(result[2].count, 0); // Mar: nothing yet
    });

    test('is oldest-first even when the current month has no items', () {
      final result = itemsPerMonth([], months: 2, now: DateTime(2026, 6, 1));

      expect(result.map((m) => m.month.month), [5, 6]);
      expect(result.every((m) => m.count == 0), isTrue);
    });

    test('crosses a year boundary correctly', () {
      final decItem = _item(id: '5', createdAt: DateTime(2025, 12, 20));
      final result = itemsPerMonth([decItem], months: 2, now: DateTime(2026, 1, 10));

      expect(result.map((m) => (m.month.year, m.month.month)), [(2025, 12), (2026, 1)]);
      expect(result[0].count, 1);
      expect(result[1].count, 0);
    });
  });

  group('topTags', () {
    test('counts occurrences and sorts most-common first', () {
      final result = topTags(['docker', 'kubernetes', 'docker', 'docker', 'kubernetes']);

      expect(result, [('docker', 3), ('kubernetes', 2)]);
    });

    test('respects the limit', () {
      final result = topTags(['a', 'b', 'b', 'c', 'c', 'c'], limit: 2);

      expect(result, [('c', 3), ('b', 2)]);
    });

    test('an empty occurrence list gives an empty result, not a crash', () {
      expect(topTags([]), isEmpty);
    });
  });
}
