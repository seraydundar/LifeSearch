import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/extensions/build_context_x.dart';
import '../../../item/presentation/widgets/item_type_icon.dart';
import '../../domain/entities/collection_suggestion.dart';
import '../providers/collection_providers.dart';
import '../providers/collection_suggestion_providers.dart';

/// Renders nothing if there are no suggestions (or no backend configured).
class CollectionSuggestionsSection extends ConsumerWidget {
  const CollectionSuggestionsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suggestionsAsync = ref.watch(collectionSuggestionsProvider);
    final dismissed = ref.watch(dismissedSuggestionKeysProvider);

    return suggestionsAsync.maybeWhen(
      data: (suggestions) {
        final visible =
            suggestions.where((s) => !dismissed.contains(suggestionKey(s))).toList();
        if (visible.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Önerilen Koleksiyonlar', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              for (final suggestion in visible) ...[
                _SuggestionCard(suggestion: suggestion),
                const SizedBox(height: 8),
              ],
            ],
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _SuggestionCard extends ConsumerWidget {
  const _SuggestionCard({required this.suggestion});

  final CollectionSuggestion suggestion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(suggestion.suggestedName,
                      style: Theme.of(context).textTheme.titleSmall),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: suggestion.items
                  .map((item) => Chip(
                        avatar: Icon(
                          itemTypeIcon(item.itemType),
                          size: 14,
                          color: itemTypeColor(item.itemType),
                        ),
                        label: Text(item.title ?? 'Untitled'),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ))
                  .toList(),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => _dismiss(ref), child: const Text('Yoksay')),
                const SizedBox(width: 4),
                FilledButton.tonal(
                  onPressed: () => _accept(context, ref),
                  child: const Text('Oluştur'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _dismiss(WidgetRef ref) {
    ref
        .read(dismissedSuggestionKeysProvider.notifier)
        .update((state) => {...state, suggestionKey(suggestion)});
  }

  Future<void> _accept(BuildContext context, WidgetRef ref) async {
    try {
      final repo = ref.read(collectionRepositoryProvider);
      final collection = await repo.createCollection(suggestion.suggestedName, isSmart: true);
      for (final item in suggestion.items) {
        await repo.addItemToCollection(collectionId: collection.id, itemId: item.itemId);
      }
      _dismiss(ref); // it's now a real collection — no reason to keep offering it
    } catch (_) {
      if (context.mounted) context.showErrorSnackBar('Koleksiyon oluşturulamadı.');
    }
  }
}
