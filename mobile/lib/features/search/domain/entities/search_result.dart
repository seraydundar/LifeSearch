import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../item/domain/entities/item.dart';

part 'search_result.freezed.dart';

/// One matched item from a semantic search — the backend already
/// deduped multiple matching chunks down to each item's best one (see
/// backend/app/services/search_service.py).
@freezed
sealed class SearchResult with _$SearchResult {
  const factory SearchResult({
    required String itemId,
    required ItemType itemType,
    String? itemTitle,
    required String snippet,
    required double similarity,
  }) = _SearchResult;
}
