import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/library_sort.dart';

enum LibraryViewMode { list, grid }

/// In-memory for now, same as `themeModeProvider` — defaults to the list
/// view every cold start. Persisting the choice is future work, not a
/// requirement of this feature.
final libraryViewModeProvider = StateProvider<LibraryViewMode>((ref) => LibraryViewMode.list);

final librarySortProvider = StateProvider<LibrarySort>((ref) => LibrarySort.newestFirst);
