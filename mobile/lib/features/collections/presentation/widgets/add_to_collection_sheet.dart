import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/extensions/build_context_x.dart';
import '../providers/collection_providers.dart';
import 'create_collection_dialog.dart';

Future<void> showAddToCollectionSheet(BuildContext context, String itemId) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => AddToCollectionSheet(itemId: itemId),
  );
}

class AddToCollectionSheet extends ConsumerWidget {
  const AddToCollectionSheet({super.key, required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collectionsAsync = ref.watch(collectionsProvider);
    final memberIdsAsync = ref.watch(itemCollectionIdsProvider(itemId));

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Koleksiyona Ekle', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            collectionsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text('Yüklenemedi: $error'),
              ),
              data: (collections) {
                if (collections.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('Henüz koleksiyonun yok.'),
                  );
                }
                final memberIds = memberIdsAsync.valueOrNull?.toSet() ?? const <String>{};
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: collections
                      .map((c) => CheckboxListTile(
                            title: Text(c.name),
                            value: memberIds.contains(c.id),
                            onChanged: (checked) => _toggle(context, ref, c.id, checked ?? false),
                          ))
                      .toList(),
                );
              },
            ),
            const SizedBox(height: 4),
            TextButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Yeni Koleksiyon'),
              onPressed: () => _createAndAdd(context, ref),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggle(BuildContext context, WidgetRef ref, String collectionId, bool checked) async {
    final repo = ref.read(collectionRepositoryProvider);
    try {
      if (checked) {
        await repo.addItemToCollection(collectionId: collectionId, itemId: itemId);
      } else {
        await repo.removeItemFromCollection(collectionId: collectionId, itemId: itemId);
      }
    } catch (_) {
      if (context.mounted) context.showErrorSnackBar('Güncellenemedi.');
    }
    ref.invalidate(itemCollectionIdsProvider(itemId));
  }

  Future<void> _createAndAdd(BuildContext context, WidgetRef ref) async {
    final name = await showCreateCollectionDialog(context);
    if (name == null || name.trim().isEmpty) return;
    try {
      final repo = ref.read(collectionRepositoryProvider);
      final created = await repo.createCollection(name.trim());
      await repo.addItemToCollection(collectionId: created.id, itemId: itemId);
    } catch (_) {
      if (context.mounted) context.showErrorSnackBar('Koleksiyon oluşturulamadı.');
    }
    ref.invalidate(itemCollectionIdsProvider(itemId));
  }
}
