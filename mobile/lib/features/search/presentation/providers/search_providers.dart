import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_provider.dart';
import '../../../../core/network/api_client_provider.dart';
import '../../../../core/network/supabase_client_provider.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../item/domain/entities/item.dart';
import '../../../item/presentation/providers/item_providers.dart';
import '../../data/local/local_search_data_source.dart';
import '../../data/local/offline_fallback_search_repository.dart';
import '../../data/local/recent_searches_data_source.dart';
import '../../data/remote/api_search_repository.dart';
import '../../domain/entities/search_filters.dart';
import '../../domain/entities/search_result.dart';
import '../../domain/repositories/search_repository.dart';

/// A `SearchResult` only ever carries an id/snippet, not the full `Item`
/// — it can't check `.private` on itself the way `itemsProvider`'s list
/// can, so Search/Related Items need this cross-check instead (Faz 11,
/// madde 2 — see docs/roadmap.md). Skipped entirely once private items
/// are revealed, same as `itemsProvider`.
///
/// Awaits `allItemsIncludingPrivateProvider.future` rather than reading
/// a `.valueOrNull` snapshot — the very first search of a session can
/// run before that stream's first emission arrives, and a `valueOrNull`
/// read at exactly that moment sees `null`/`loading`, which would have
/// let a private item's result straight through unfiltered.
///
/// If that provider itself errors (no signed-in session — `.future`
/// rethrows a `StreamProvider`'s error state, unlike `.valueOrNull`,
/// which swallows it into `null`) this falls back to showing every
/// result rather than failing the whole search over a privacy check
/// that has nothing to check against yet.
Future<List<SearchResult>> _hidePrivateResults(Ref ref, List<SearchResult> results) async {
  if (ref.read(privateItemsRevealedProvider)) return results;
  List<Item> items;
  try {
    items = await ref.read(allItemsIncludingPrivateProvider.future);
  } catch (_) {
    return results;
  }
  final privateIds = {for (final item in items) if (item.private) item.id};
  return results.where((r) => !privateIds.contains(r.itemId)).toList();
}

/// `Supabase.instance` asserts if `Supabase.initialize()` never ran —
/// harmless in the real app (`main()` always initializes it first, see
/// `supabaseClientProvider`'s docstring) but a widget test that overrides
/// `searchRepositoryProvider` (bypassing the network entirely, same as
/// `SyncService._currentUserIdOrNull()`'s reasoning for `AuthFailure`)
/// would otherwise hit this by way of `SearchController`'s recent-search
/// bookkeeping, which has nothing to do with what that test is checking.
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
  // `ref.watch` (not the one-off `_currentUserIdOrNull` read below) so
  // this rebuilds across an account switch — see `currentUserIdProvider`'s
  // docstring (Faz 12, docs/roadmap.md). Previously bound to whichever
  // account was signed in when this provider was first watched, the same
  // bug `itemsProvider` had.
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return Stream.value(const []);
  return ref.watch(recentSearchesDataSourceProvider).watchRecent(userId);
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
    state = await AsyncValue.guard(() async {
      final results = await ref.read(searchRepositoryProvider).search(trimmed, filters: filters);
      return _hidePrivateResults(ref, results);
    });

    final userId = _currentUserIdOrNull(ref);
    if (!state.hasError && userId != null) {
      await ref.read(recentSearchesDataSourceProvider).record(userId, trimmed);
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
  (ref, itemId) async {
    final results = await ref.watch(searchRepositoryProvider).related(itemId);
    return _hidePrivateResults(ref, results);
  },
);
