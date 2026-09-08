import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_provider.dart';
import '../../../../core/network/api_client_provider.dart';
import '../../../../core/network/supabase_client_provider.dart';
import '../../data/local/local_search_data_source.dart';
import '../../data/local/offline_fallback_search_repository.dart';
import '../../data/local/recent_searches_data_source.dart';
import '../../data/remote/api_search_repository.dart';
import '../../domain/entities/search_filters.dart';
import '../../domain/entities/search_result.dart';
import '../../domain/repositories/search_repository.dart';

final localSearchDataSourceProvider = Provider<LocalSearchDataSource>((ref) {
  return LocalSearchDataSource(ref.watch(appDatabaseProvider));
});

final searchRepositoryProvider = Provider<SearchRepository>((ref) {
  return OfflineFallbackSearchRepository(
    remote: ApiSearchRepository(ref.watch(apiClientProvider)),
    local: ref.watch(localSearchDataSourceProvider),
    currentUserId: () => ref.read(supabaseClientProvider).auth.currentUser?.id,
  );
});

final recentSearchesDataSourceProvider = Provider<RecentSearchesDataSource>((ref) {
  return RecentSearchesDataSource(ref.watch(appDatabaseProvider));
});

final recentSearchesProvider = StreamProvider<List<String>>((ref) {
  return ref.watch(recentSearchesDataSourceProvider).watchRecent();
});

/// Active type/date filters (requirements doc, section 21) — a plain
/// `StateProvider` since the Search tab is the only writer and there's no
/// async work involved in just holding the selection.
final searchFiltersProvider = StateProvider<SearchFilters>((ref) => const SearchFilters());

final searchControllerProvider =
    AsyncNotifierProvider<SearchController, List<SearchResult>>(SearchController.new);

class SearchController extends AsyncNotifier<List<SearchResult>> {
  String _lastQuery = '';

  @override
  List<SearchResult> build() => [];

  Future<void> search(String query) async {
    final trimmed = query.trim();
    _lastQuery = trimmed;
    if (trimmed.isEmpty) {
      state = const AsyncData([]);
      return;
    }

    state = const AsyncLoading();
    final filters = ref.read(searchFiltersProvider);
    state = await AsyncValue.guard(
      () => ref.read(searchRepositoryProvider).search(trimmed, filters: filters),
    );

    if (!state.hasError) {
      await ref.read(recentSearchesDataSourceProvider).record(trimmed);
    }
  }

  /// Re-runs the last query under the current filters — called when the
  /// user changes a filter chip while a search is already showing results.
  Future<void> researchWithCurrentFilters() async {
    if (_lastQuery.isEmpty) return;
    await search(_lastQuery);
  }

  void clear() {
    _lastQuery = '';
    state = const AsyncData([]);
  }
}

/// Items whose content is close to the given one — for the "Related"
/// section on the item detail screen. Keyed by item id so switching
/// between items doesn't reuse a stale result.
final relatedItemsProvider = FutureProvider.autoDispose.family<List<SearchResult>, String>(
  (ref, itemId) => ref.watch(searchRepositoryProvider).related(itemId),
);
