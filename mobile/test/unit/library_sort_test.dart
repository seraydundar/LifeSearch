import 'package:flutter_test/flutter_test.dart';
import 'package:lifesearch/features/item/domain/entities/item.dart';
import 'package:lifesearch/features/library/domain/library_sort.dart';

void main() {
  Item item({required String id, String? title, String? originalFilename, DateTime? createdAt}) {
    return Item(
      id: id,
      type: ItemType.note,
      title: title,
      originalFilename: originalFilename,
      processingStatus: 'completed',
      favorite: false,
      createdAt: createdAt ?? DateTime(2026, 1, 1),
    );
  }

  test('newestFirst orders by createdAt descending', () {
    final a = item(id: 'a', title: 'A', createdAt: DateTime(2026, 1, 1));
    final b = item(id: 'b', title: 'B', createdAt: DateTime(2026, 3, 1));
    final c = item(id: 'c', title: 'C', createdAt: DateTime(2026, 2, 1));

    final sorted = sortItems([a, b, c], LibrarySort.newestFirst);

    expect(sorted.map((i) => i.id), ['b', 'c', 'a']);
  });

  test('oldestFirst orders by createdAt ascending', () {
    final a = item(id: 'a', title: 'A', createdAt: DateTime(2026, 1, 1));
    final b = item(id: 'b', title: 'B', createdAt: DateTime(2026, 3, 1));
    final c = item(id: 'c', title: 'C', createdAt: DateTime(2026, 2, 1));

    final sorted = sortItems([a, b, c], LibrarySort.oldestFirst);

    expect(sorted.map((i) => i.id), ['a', 'c', 'b']);
  });

  test('nameAscending orders by displayTitle, case-insensitively', () {
    final a = item(id: 'a', title: 'banana');
    final b = item(id: 'b', title: 'Apple');
    final c = item(id: 'c', title: 'cherry');

    final sorted = sortItems([a, b, c], LibrarySort.nameAscending);

    expect(sorted.map((i) => i.id), ['b', 'a', 'c']);
  });

  test('nameAscending falls back to originalFilename, then "Untitled"', () {
    final withTitle = item(id: 'a', title: 'Zebra');
    final withFilename = item(id: 'b', originalFilename: 'apple.pdf');
    final untitled = item(id: 'c');

    final sorted = sortItems([withTitle, withFilename, untitled], LibrarySort.nameAscending);

    // "apple.pdf" < "Untitled" < "Zebra"
    expect(sorted.map((i) => i.id), ['b', 'c', 'a']);
  });

  test('does not mutate the input list', () {
    final a = item(id: 'a', createdAt: DateTime(2026, 1, 1));
    final b = item(id: 'b', createdAt: DateTime(2026, 2, 1));
    final original = [a, b];

    sortItems(original, LibrarySort.newestFirst);

    expect(original.map((i) => i.id), ['a', 'b']);
  });
}
