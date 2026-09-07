import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/extensions/build_context_x.dart';
import '../../../item/presentation/widgets/item_list_tile.dart';
import '../providers/collection_providers.dart';
import '../widgets/create_collection_dialog.dart';

class CollectionDetailScreen extends ConsumerWidget {
  const CollectionDetailScreen({super.key, required this.collectionId, required this.name});

  final String collectionId;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(collectionItemsProvider(collectionId));

    return Scaffold(
      appBar: AppBar(
        title: Text(name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Yeniden adlandır',
            onPressed: () => _rename(context, ref),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Koleksiyonu sil',
            onPressed: () => _delete(context, ref),
          ),
        ],
      ),
      body: itemsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Yüklenemedi: $error')),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.folder_open_outlined,
                        size: 40, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(height: 12),
                    Text(
                      'Bu koleksiyon henüz boş.\nBir içeriğin detayından "Koleksiyona Ekle" ile buraya taşıyabilirsin.',
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = items[index];
              return ItemListTile(
                item: item,
                trailing: IconButton(
                  icon: const Icon(Icons.remove_circle_outline, size: 20),
                  tooltip: 'Koleksiyondan çıkar',
                  onPressed: () => ref
                      .read(collectionRepositoryProvider)
                      .removeItemFromCollection(collectionId: collectionId, itemId: item.id),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final newName = await showCreateCollectionDialog(context, initialName: name);
    if (newName == null || newName.trim().isEmpty) return;
    try {
      await ref.read(collectionRepositoryProvider).renameCollection(collectionId, newName.trim());
    } catch (_) {
      if (context.mounted) context.showErrorSnackBar('Güncellenemedi.');
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Koleksiyonu sil'),
        content: Text('"$name" silinecek. İçindeki öğeler silinmez.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false), child: const Text('Vazgeç')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Sil')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(collectionRepositoryProvider).deleteCollection(collectionId);
      if (context.mounted && context.canPop()) context.pop();
    } catch (_) {
      if (context.mounted) context.showErrorSnackBar('Silinemedi.');
    }
  }
}
