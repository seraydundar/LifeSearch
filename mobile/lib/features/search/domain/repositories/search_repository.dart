import '../entities/search_filters.dart';
import '../entities/search_result.dart';

abstract interface class SearchRepository {
  /// [includePrivate] must only ever be the live value of `privateItemsRevealedProvider`.
  Future<List<SearchResult>> search(
    String query, {
    SearchFilters filters = const SearchFilters(),
    bool includePrivate = false,
  });

  /// No query text involved. Same [includePrivate] contract as [search].
  Future<List<SearchResult>> related(String itemId, {bool includePrivate = false});
}
