import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../item/domain/entities/item.dart';

part 'search_filters.freezed.dart';

/// Empty `types` means no type filter. `dateFrom`/`dateTo` are independently optional.
@freezed
sealed class SearchFilters with _$SearchFilters {
  const factory SearchFilters({
    @Default(<ItemType>{}) Set<ItemType> types,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) = _SearchFilters;

  const SearchFilters._();

  bool get isEmpty => types.isEmpty && dateFrom == null && dateTo == null;
}
