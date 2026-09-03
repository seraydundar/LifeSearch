import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_provider.dart';
import '../../../../core/network/api_client_provider.dart';
import '../../data/local/recent_searches_data_source.dart';
import '../../data/remote/api_search_repository.dart';
import '../../domain/entities/search_result.dart';
import '../../domain/repositories/search_repository.dart';

final searchRepositoryProvider = Provider<SearchRepository>((ref) {
  return ApiSearchRepository(ref.watch(apiClientProvider));
});

final recentSearchesDataSourceProvider = Provider<RecentSearchesDataSource>((ref) {
  return RecentSearchesDataSource(ref.watch(appDatabaseProvider));
});

final recentSearchesProvider = StreamProvider<List<String>>((ref) {
  return ref.watch(recentSearchesDataSourceProvider).watchRecent();
});

final searchControllerProvider =
    AsyncNotifierProvider<SearchController, List<SearchResult>>(SearchController.new);

class SearchController extends AsyncNotifier<List<SearchResult>> {
  @override
  List<SearchResult> build() => [];

  Future<void> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      state = const AsyncData([]);
      return;
    }

    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(searchRepositoryProvider).search(trimmed));

    if (!state.hasError) {
      await ref.read(recentSearchesDataSourceProvider).record(trimmed);
    }
  }

  void clear() => state = const AsyncData([]);
}
