import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/extracted_entity.dart';
import '../providers/item_providers.dart';

IconData _entityTypeIcon(EntityType type) {
  return switch (type) {
    EntityType.person => Icons.person_outline,
    EntityType.place => Icons.place_outlined,
    EntityType.organization => Icons.apartment_outlined,
    EntityType.date => Icons.event_outlined,
    // P3 (docs/requirements-audit-2026-09-13.md):
    EntityType.product => Icons.shopping_bag_outlined,
    EntityType.price => Icons.sell_outlined,
    EntityType.website => Icons.link_outlined,
    EntityType.technology => Icons.memory_outlined,
  };
}

/// AI-extracted named entities (requirements doc, section 44-48) — same
/// role as `TagsRow`, just typed: each chip carries an icon for what kind
/// of entity it is (person/place/organization/date). Tapping one jumps to
/// its search results, same as a tag. Renders nothing while loading, on
/// error, or when the item has none yet — a bonus, not core content.
class EntitiesRow extends ConsumerWidget {
  const EntitiesRow({super.key, required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entitiesAsync = ref.watch(itemEntitiesProvider(itemId));
    return entitiesAsync.maybeWhen(
      data: (entities) {
        if (entities.isEmpty) return const SizedBox.shrink();
        return Wrap(
          spacing: 6,
          runSpacing: 6,
          children: entities
              .map((entity) => ActionChip(
                    avatar: Icon(_entityTypeIcon(entity.type), size: 16),
                    label: Text(entity.name),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => context.push('/search', extra: entity.name),
                  ))
              .toList(),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}
