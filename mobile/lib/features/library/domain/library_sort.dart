import '../../item/domain/entities/item.dart';

enum LibrarySort { newestFirst, oldestFirst, nameAscending, byType }

/// Pure — Library applies this after the favorites filter, before handing
/// items to either the list or grid layout.
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
      // P3 (docs/requirements-audit-2026-09-13.md) — grouped alphabetically
      // by the type's own name (stable and needs no separate display-order
      // table to keep in sync as types are added), newest first within
      // each group, same tiebreak `newestFirst` itself uses.
      sorted.sort((a, b) {
        final byType = a.type.name.compareTo(b.type.name);
        return byType != 0 ? byType : b.createdAt.compareTo(a.createdAt);
      });
  }
  return sorted;
}
