import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../item/domain/entities/item.dart';

part 'search_filters.freezed.dart';

/// Metadata filters (requirements doc, section 21) — "All/Images/
/// Documents/Notes/Links/Audio" and a date range. Empty `types` means no
/// type filter; `dateFrom == null` means no date filter.
@freezed
sealed class SearchFilters with _$SearchFilters {
  const factory SearchFilters({
    @Default(<ItemType>{}) Set<ItemType> types,
    DateTime? dateFrom,
  }) = _SearchFilters;

  const SearchFilters._();

  bool get isEmpty => types.isEmpty && dateFrom == null;
}
