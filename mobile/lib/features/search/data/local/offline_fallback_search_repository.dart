import '../../domain/entities/search_filters.dart';
import '../../domain/entities/search_result.dart';
import '../../domain/repositories/search_repository.dart';
import 'local_search_data_source.dart';

/// Wraps the real (semantic/hybrid) search with a local keyword fallback
/// (requirements doc: "offline-first ... + offline keyword search") —
/// tried only when the remote call itself fails (no connectivity, the
/// backend unreachable, no `BACKEND_URL` configured, ...), never as a
/// first choice, since local keyword matching is strictly worse than the
/// AI-backed result set. `related()` has no offline analog — it needs
/// embeddings — so it always goes straight to remote.
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
  }) async {
    try {
      return await _remote.search(query, filters: filters);
    } catch (_) {
      return _local.search(_currentUserId(), query, filters: filters);
    }
  }

  @override
  Future<List<SearchResult>> related(String itemId) => _remote.related(itemId);
}
