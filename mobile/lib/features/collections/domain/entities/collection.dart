import 'package:freezed_annotation/freezed_annotation.dart';

part 'collection.freezed.dart';

/// A user-made grouping of items (requirements doc, section 28). `isSmart`
/// is reserved for AI-suggested collections — nothing in the app creates
/// one with `isSmart: true` yet, see infra/supabase/migrations/0008_collections.sql.
@freezed
sealed class Collection with _$Collection {
  const factory Collection({
    required String id,
    required String name,
    required bool isSmart,
    required DateTime createdAt,
  }) = _Collection;
}
