import 'dart:async';

import 'package:lifesearch/features/item/domain/entities/item.dart';
import 'package:lifesearch/features/search/domain/entities/search_filters.dart';
import 'package:lifesearch/features/search/domain/entities/search_result.dart';
import 'package:lifesearch/features/search/domain/repositories/search_repository.dart';

class FakeSearchRepository implements SearchRepository {
  FakeSearchRepository({
    this.resultsToReturn = const [],
    this.relatedToReturn = const [],
    this.errorToThrow,
    this.resultsByQuery,
    this.gates,
  });

  List<SearchResult> resultsToReturn;
  List<SearchResult> relatedToReturn;
  Object? errorToThrow;
  String? lastQuery;
  SearchFilters? lastFilters;
  String? lastRelatedItemId;
  bool? lastIncludePrivate;
  bool? lastRelatedIncludePrivate;

  /// Per-query results, for tests that need two different queries to
  /// resolve with two different result sets. Falls back to
  /// [resultsToReturn] for any query not present here.
  Map<String, List<SearchResult>>? resultsByQuery;

  /// Optional per-query completers that [search] awaits before
  /// returning, so a test can control the order in which two
  /// concurrent `search()` calls actually resolve — see the search
  /// race condition regression test (Faz 12, madde 13, docs/roadmap.md).
  Map<String, Completer<void>>? gates;

  @override
  Future<List<SearchResult>> search(
    String query, {
    SearchFilters filters = const SearchFilters(),
    bool includePrivate = false,
  }) async {
    lastQuery = query;
    lastFilters = filters;
    lastIncludePrivate = includePrivate;
    final gate = gates?[query];
    if (gate != null) await gate.future;
    if (errorToThrow != null) throw errorToThrow!;
    return resultsByQuery?[query] ?? resultsToReturn;
  }

  @override
  Future<List<SearchResult>> related(String itemId, {bool includePrivate = false}) async {
    lastRelatedItemId = itemId;
    lastRelatedIncludePrivate = includePrivate;
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
