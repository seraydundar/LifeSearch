import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_provider.dart';
import '../../../../core/network/api_client_provider.dart';
import '../../../../core/network/supabase_client_provider.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../item/presentation/providers/item_providers.dart';
import '../../data/local/local_search_data_source.dart';
import '../../data/local/offline_fallback_search_repository.dart';
import '../../data/local/recent_searches_data_source.dart';
import '../../data/remote/api_search_repository.dart';
import '../../domain/entities/search_filters.dart';
import '../../domain/entities/search_result.dart';
import '../../domain/repositories/search_repository.dart';

/// Must await `.future`, not read `.valueOrNull` (race on first emission), and must
/// rethrow rather than return unfiltered results on error — fails closed, not open.
Future<List<SearchResult>> _hidePrivateResults(Ref ref, List<SearchResult> results) async {
  if (ref.read(privateItemsRevealedProvider)) return results;
  final items = await ref.read(allItemsIncludingPrivateProvider.future);
  final privateIds = {for (final item in items) if (item.private) item.id};
  return results.where((r) => !privateIds.contains(r.itemId)).toList();
}

/// Catches `Supabase.instance`'s assert when uninitialized, which a widget test
/// overriding `searchRepositoryProvider` would otherwise hit via recent-search bookkeeping.
String? _currentUserIdOrNull(Ref ref) {
  try {
    return ref.read(supabaseClientProvider).auth.currentUser?.id;
  } catch (_) {
    return null;
  }
}

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
  // ref.watch (not a one-off read) so this rebuilds on account switch.
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return Stream.value(const []);
  return ref.watch(recentSearchesDataSourceProvider).watchRecent(userId);
});

final searchFiltersProvider = StateProvider<SearchFilters>((ref) => const SearchFilters());

final searchControllerProvider =
    AsyncNotifierProvider<SearchController, List<SearchResult>>(SearchController.new);

class SearchController extends AsyncNotifier<List<SearchResult>> {
  String _lastQuery = '';

  /// Bumped by every search()/clear(); a call discards its own result if this has
  /// moved on by the time it resolves, so a stale response can't overwrite a newer one.
  int _searchGeneration = 0;

  @override
  List<SearchResult> build() {
    // Results are a one-shot snapshot, so re-filter when reveal flips back off.
    ref.listen(privateItemsRevealedProvider, (previous, next) {
      if (previous == true && next == false) _reapplyPrivacyFilter();
    });
    // Clear on account switch so a previous account's results don't linger.
    ref.listen(currentUserIdProvider, (previous, next) {
      if (previous != next) clear();
    });
    return [];
  }

  Future<void> _reapplyPrivacyFilter() async {
    final current = state.valueOrNull;
    if (current == null || current.isEmpty) return;
    state = await AsyncValue.guard(() => _hidePrivateResults(ref, current));
  }

  Future<void> search(String query) async {
    final trimmed = query.trim();
    _lastQuery = trimmed;
    final generation = ++_searchGeneration;

    if (trimmed.isEmpty) {
      state = const AsyncData([]);
      return;
    }

    state = const AsyncLoading();
    final filters = ref.read(searchFiltersProvider);
    // `_hidePrivateResults` below re-checks the response, since reveal can flip off
    // between this read and the response landing.
    final includePrivate = ref.read(privateItemsRevealedProvider);
    final result = await AsyncValue.guard(() async {
      final results = await ref
          .read(searchRepositoryProvider)
          .search(trimmed, filters: filters, includePrivate: includePrivate);
      return _hidePrivateResults(ref, results);
    });

    if (generation != _searchGeneration) return;
    state = result;

    final userId = _currentUserIdOrNull(ref);
    if (!state.hasError && userId != null) {
      await ref.read(recentSearchesDataSourceProvider).record(userId, trimmed);
    }
  }

  Future<void> researchWithCurrentFilters() async {
    if (_lastQuery.isEmpty) return;
    await search(_lastQuery);
  }

  void clear() {
    _lastQuery = '';
    // Invalidates any in-flight search() so it can't overwrite this reset.
    _searchGeneration++;
    state = const AsyncData([]);
  }
}

/// Keyed by item id so switching between items doesn't reuse a stale result.
final relatedItemsProvider = FutureProvider.autoDispose.family<List<SearchResult>, String>(
  (ref, itemId) async {
    final includePrivate = ref.watch(privateItemsRevealedProvider);
    final results = await ref
        .watch(searchRepositoryProvider)
        .related(itemId, includePrivate: includePrivate);
    return _hidePrivateResults(ref, results);
  },
);
