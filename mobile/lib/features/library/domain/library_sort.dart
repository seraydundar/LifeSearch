import '../../item/domain/entities/item.dart';

enum LibrarySort { newestFirst, oldestFirst, nameAscending }

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
  }
  return sorted;
}
