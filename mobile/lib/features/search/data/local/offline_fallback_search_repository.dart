import '../../domain/entities/search_filters.dart';
import '../../domain/entities/search_result.dart';
import '../../domain/repositories/search_repository.dart';
import 'local_search_data_source.dart';

/// Local keyword search is tried only when the remote call fails, never as a first
/// choice. `related()` has no offline analog (needs embeddings), so it always goes remote.
class OfflineFallbackSearchRepository implements SearchRepository {
  OfflineFallbackSearchRepository({
    required SearchRepository remote,
    required LocalSearchDataSource local,
    required String? Function() currentUserId,
  })  : _remote = remote,
        _local = local,
        _currentUserId = currentUserId;

  final SearchRepository _remote;
  final LocalSearchDataSource _local;
  final String? Function() _currentUserId;

  @override
  Future<List<SearchResult>> search(
    String query, {
    SearchFilters filters = const SearchFilters(),
    bool includePrivate = false,
  }) async {
    try {
      return await _remote.search(query, filters: filters, includePrivate: includePrivate);
    } catch (_) {
      return _local.search(
        _currentUserId(),
        query,
        filters: filters,
        includePrivate: includePrivate,
      );
    }
  }

  @override
  Future<List<SearchResult>> related(String itemId, {bool includePrivate = false}) =>
      _remote.related(itemId, includePrivate: includePrivate);
}
