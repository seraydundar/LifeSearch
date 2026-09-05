import '../entities/search_filters.dart';
import '../entities/search_result.dart';

abstract interface class SearchRepository {
  Future<List<SearchResult>> search(String query, {SearchFilters filters});

  /// Other items whose content is semantically close to this one
  /// (requirements doc, section 47) — no query text involved.
  Future<List<SearchResult>> related(String itemId);
}
