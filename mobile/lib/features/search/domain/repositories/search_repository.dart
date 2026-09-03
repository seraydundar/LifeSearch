import '../entities/search_result.dart';

abstract interface class SearchRepository {
  Future<List<SearchResult>> search(String query);
}
