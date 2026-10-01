import 'package:freezed_annotation/freezed_annotation.dart';

part 'extracted_entity.freezed.dart';

/// Mirrors the `type` check constraint on the `entities` table.
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

/// An AI-extracted named entity found in an item's content, unlike a
/// plain tag, this is structured and typed.
@freezed
sealed class ExtractedEntity with _$ExtractedEntity {
  const factory ExtractedEntity({
    required String name,
    required EntityType type,
  }) = _ExtractedEntity;
}
