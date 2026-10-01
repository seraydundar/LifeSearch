import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/extensions/build_context_x.dart';
import '../providers/collection_providers.dart';
import 'create_collection_dialog.dart';

class CollectionsBar extends ConsumerWidget {
  const CollectionsBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collectionsAsync = ref.watch(collectionsProvider);

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        children: [
          ActionChip(
            avatar: const Icon(Icons.add, size: 18),
            label: const Text('Yeni Koleksiyon'),
            onPressed: () => _createCollection(context, ref),
          ),
          const SizedBox(width: 8),
          ...collectionsAsync.maybeWhen(
            data: (collections) => collections
                .map(
                  (c) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      avatar: const Icon(Icons.folder_outlined, size: 18),
                      label: Text(c.name),
                      onPressed: () => context.push('/collections/${c.id}', extra: c.name),
                    ),
                  ),
                )
                .toList(),
            orElse: () => const [],
          ),
        ],
      ),
    );
  }

  Future<void> _createCollection(BuildContext context, WidgetRef ref) async {
    final name = await showCreateCollectionDialog(context);
    if (name == null || name.trim().isEmpty) return;
    try {
      await ref.read(collectionRepositoryProvider).createCollection(name.trim());
    } catch (_) {
      if (context.mounted) context.showErrorSnackBar('Koleksiyon oluşturulamadı.');
    }
  }
}
