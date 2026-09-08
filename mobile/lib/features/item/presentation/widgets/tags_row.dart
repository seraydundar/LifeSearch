import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/item_providers.dart';

/// AI-generated tags (requirements doc, section 8-12) — used by both item
/// detail and the note editor. Tapping a tag jumps straight to that tag's
/// search results. Renders nothing while loading, on error, or when the
/// item has no tags yet (still processing, or the AI provider produced
/// none) — this is a bonus, not core content.
class TagsRow extends ConsumerWidget {
  const TagsRow({super.key, required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tagsAsync = ref.watch(itemTagsProvider(itemId));
    return tagsAsync.maybeWhen(
      data: (tags) {
        if (tags.isEmpty) return const SizedBox.shrink();
        return Wrap(
          spacing: 6,
          runSpacing: 6,
          children: tags
              .map((tag) => ActionChip(
                    label: Text(tag),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => context.push('/search', extra: tag),
                  ))
              .toList(),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}
