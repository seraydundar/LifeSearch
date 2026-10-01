import '../entities/collection_suggestion.dart';

abstract interface class CollectionSuggestionRepository {
  /// Never throws — a failure just means no suggestions this time.
  Future<List<CollectionSuggestion>> fetchSuggestions();
}
