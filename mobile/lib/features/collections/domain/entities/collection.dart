import 'package:freezed_annotation/freezed_annotation.dart';

part 'collection.freezed.dart';

/// `isSmart` is reserved for AI-suggested collections; nothing creates one with it true yet.
@freezed
sealed class Collection with _$Collection {
  const factory Collection({
    required String id,
    required String name,
    required bool isSmart,
    required DateTime createdAt,
  }) = _Collection;
}
