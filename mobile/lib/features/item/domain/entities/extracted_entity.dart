import 'package:freezed_annotation/freezed_annotation.dart';

part 'extracted_entity.freezed.dart';

/// Mirrors the `type` check constraint on the `entities` table (see
/// infra/supabase/migrations/0011_entities.sql, extended by P3's
/// 0020_entity_types_extend.sql — docs/requirements-audit-2026-09-13.md).
enum EntityType { person, place, organization, date, product, price, website, technology }

extension EntityTypeX on EntityType {
  String get dbValue => name;

  static EntityType fromDbValue(String value) {
    return EntityType.values.firstWhere(
      (type) => type.name == value,
      orElse: () => EntityType.person,
    );
  }
}

/// An AI-extracted named entity (requirements doc, section 44-48) — a
/// person, place, organization, or date the backend's pipeline found
/// mentioned in an item's content. Structured/typed, unlike a plain tag.
@freezed
sealed class ExtractedEntity with _$ExtractedEntity {
  const factory ExtractedEntity({
    required String name,
    required EntityType type,
  }) = _ExtractedEntity;
}
