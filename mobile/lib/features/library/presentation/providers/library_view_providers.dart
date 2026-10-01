import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/library_sort.dart';

enum LibraryViewMode { list, grid }

/// In-memory only; always starts on list view each cold start.
final libraryViewModeProvider = StateProvider<LibraryViewMode>((ref) => LibraryViewMode.list);

final librarySortProvider = StateProvider<LibrarySort>((ref) => LibrarySort.newestFirst);
