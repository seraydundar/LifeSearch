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
/// **Fails closed, not open** (Faz 12, madde 5 — denetim düzeltmesi, see
/// docs/roadmap.md): if that provider itself errors, this used to fall
/// back to showing every result — including private ones — rather than
/// failing the whole search. That was reasoning about an *unconfigured
/// test fixture* (no `itemRepositoryProvider` override, so nothing to
/// check against), but it applied to every real error too: a genuine
/// Drift hiccup in production would have silently leaked private items
/// into the results list instead of surfacing as a failure. Now it
/// rethrows — `SearchController.search()`'s `AsyncValue.guard` turns
/// that into the same visible error state a real network failure gets
/// (see `search_tab.dart`'s `error:` branch), and `relatedItemsProvider`
/// already hides its whole section on any error (`item_detail_screen
/// .dart`) — neither silently shows something that might be private.
Future<List<SearchResult>> _hidePrivateResults(Ref ref, List<SearchResult> results) async {
  if (ref.read(privateItemsRevealedProvider)) return results;
  final items = await ref.read(allItemsIncludingPrivateProvider.future);
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
  List<SearchResult> build() {
    // Faz 12, madde 5 (denetim düzeltmesi — see docs/roadmap.md): a
    // result set fetched *while* private items were revealed doesn't
    // re-filter itself when the reveal flag flips back off (e.g. the
    // app is backgrounded — see `AppLockGate`'s lifecycle observer) —
    // every other private-item entry point (Home, Library) re-hides
    // live because they read `itemsProvider` reactively; this list is a
    // one-shot snapshot from whenever `search()` last ran, so without
    // this listener a private item's result would keep showing in an
    // already-displayed list even after reveal turns back off.
    ref.listen(privateItemsRevealedProvider, (previous, next) {
      if (previous == true && next == false) _reapplyPrivacyFilter();
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
