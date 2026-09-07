import '../entities/collection_suggestion.dart';

abstract interface class CollectionSuggestionRepository {
  /// Never throws — a suggestion failure (no backend configured, network
  /// error, ...) just means no suggestions this time, not a broken
  /// Library screen. See `ApiCollectionSuggestionRepository`.
  Future<List<CollectionSuggestion>> fetchSuggestions();
}
