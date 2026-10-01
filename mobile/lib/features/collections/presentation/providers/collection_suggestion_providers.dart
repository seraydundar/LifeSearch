import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client_provider.dart';
import '../../data/remote/api_collection_suggestion_repository.dart';
import '../../domain/entities/collection_suggestion.dart';
import '../../domain/repositories/collection_suggestion_repository.dart';

final collectionSuggestionRepositoryProvider = Provider<CollectionSuggestionRepository>((ref) {
  return ApiCollectionSuggestionRepository(ref.watch(apiClientProvider));
});

final collectionSuggestionsProvider =
    FutureProvider.autoDispose<List<CollectionSuggestion>>((ref) {
  return ref.watch(collectionSuggestionRepositoryProvider).fetchSuggestions();
});

/// Not persisted — a dismissal means "not now", not a stored preference.
final dismissedSuggestionKeysProvider = StateProvider.autoDispose<Set<String>>((ref) => {});
