import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../item/domain/entities/item.dart';

part 'collection_suggestion.freezed.dart';

@freezed
sealed class SuggestedItem with _$SuggestedItem {
  const factory SuggestedItem({
    required String itemId,
    String? title,
    required ItemType itemType,
  }) = _SuggestedItem;
}

/// An AI-clustered group of not-yet-collected items; nothing is created until accepted.
@freezed
sealed class CollectionSuggestion with _$CollectionSuggestion {
  const factory CollectionSuggestion({
    required String suggestedName,
    required List<SuggestedItem> items,
  }) = _CollectionSuggestion;
}

/// Suggestions have no server-side id (recomputed each fetch), so identity is derived from member items.
String suggestionKey(CollectionSuggestion suggestion) {
  final ids = suggestion.items.map((i) => i.itemId).toList()..sort();
  return ids.join(',');
}
