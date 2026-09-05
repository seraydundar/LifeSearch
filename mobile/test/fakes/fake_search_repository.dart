import 'package:lifesearch/features/item/domain/entities/item.dart';
import 'package:lifesearch/features/search/domain/entities/search_filters.dart';
import 'package:lifesearch/features/search/domain/entities/search_result.dart';
import 'package:lifesearch/features/search/domain/repositories/search_repository.dart';

class FakeSearchRepository implements SearchRepository {
  FakeSearchRepository({
    this.resultsToReturn = const [],
    this.relatedToReturn = const [],
    this.errorToThrow,
  });

  List<SearchResult> resultsToReturn;
  List<SearchResult> relatedToReturn;
  Object? errorToThrow;
  String? lastQuery;
  SearchFilters? lastFilters;
  String? lastRelatedItemId;

  @override
  Future<List<SearchResult>> search(String query, {SearchFilters filters = const SearchFilters()}) async {
    lastQuery = query;
    lastFilters = filters;
    if (errorToThrow != null) throw errorToThrow!;
    return resultsToReturn;
  }

  @override
  Future<List<SearchResult>> related(String itemId) async {
    lastRelatedItemId = itemId;
    if (errorToThrow != null) throw errorToThrow!;
    return relatedToReturn;
  }
}

SearchResult fakeSearchResult({
  String itemId = 'item-1',
  ItemType itemType = ItemType.note,
  String? itemTitle = 'Docker Notes',
  String snippet = 'Docker container ile image arasindaki fark...',
  double similarity = 0.9,
}) {
  return SearchResult(
    itemId: itemId,
    itemType: itemType,
    itemTitle: itemTitle,
    snippet: snippet,
    similarity: similarity,
  );
}
