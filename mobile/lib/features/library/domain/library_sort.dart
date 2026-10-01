import '../../item/domain/entities/item.dart';

enum LibrarySort { newestFirst, oldestFirst, nameAscending, byType }

/// Applied after the favorites filter, before list/grid layout.
List<Item> sortItems(List<Item> items, LibrarySort sort) {
  final sorted = List<Item>.of(items);
  switch (sort) {
    case LibrarySort.newestFirst:
      sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    case LibrarySort.oldestFirst:
      sorted.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    case LibrarySort.nameAscending:
      sorted.sort(
        (a, b) => a.displayTitle.toLowerCase().compareTo(b.displayTitle.toLowerCase()),
      );
    case LibrarySort.byType:
      // Grouped by type name (stable, no display-order table to maintain), newest first within each group.
      sorted.sort((a, b) {
        final byType = a.type.name.compareTo(b.type.name);
        return byType != 0 ? byType : b.createdAt.compareTo(a.createdAt);
      });
  }
  return sorted;
}
