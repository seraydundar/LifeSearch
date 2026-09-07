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

/// An AI-clustered group of the user's not-yet-collected items
/// (requirements doc, section 129) — see
/// `backend/app/services/collection_suggestion_service.py`. Purely a
/// suggestion: nothing is created until the user accepts it.
@freezed
sealed class CollectionSuggestion with _$CollectionSuggestion {
  const factory CollectionSuggestion({
    required String suggestedName,
    required List<SuggestedItem> items,
  }) = _CollectionSuggestion;
}

/// Stable identity for a suggestion across rebuilds — used to remember
/// which ones the user dismissed this session. Suggestions have no
/// server-side id (they're recomputed each fetch, not stored), so this
/// is derived from the one thing that actually identifies a cluster:
/// which items are in it.
String suggestionKey(CollectionSuggestion suggestion) {
  final ids = suggestion.items.map((i) => i.itemId).toList()..sort();
  return ids.join(',');
}
