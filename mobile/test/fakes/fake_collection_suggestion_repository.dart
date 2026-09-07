import 'package:lifesearch/features/collections/domain/entities/collection_suggestion.dart';
import 'package:lifesearch/features/collections/domain/repositories/collection_suggestion_repository.dart';

class FakeCollectionSuggestionRepository implements CollectionSuggestionRepository {
  FakeCollectionSuggestionRepository({this.suggestions = const []});

  List<CollectionSuggestion> suggestions;

  @override
  Future<List<CollectionSuggestion>> fetchSuggestions() async => suggestions;
}
