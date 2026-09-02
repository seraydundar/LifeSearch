import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../item/domain/entities/item.dart';
import '../../../item/presentation/providers/item_providers.dart';
import '../../../item/presentation/widgets/item_type_icon.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  bool _favoritesOnly = false;

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(itemsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        actions: [
          IconButton(
            icon: Icon(_favoritesOnly ? Icons.star : Icons.star_border),
            tooltip: 'Sadece favoriler',
            onPressed: () => setState(() => _favoritesOnly = !_favoritesOnly),
          ),
        ],
      ),
      body: itemsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Yüklenemedi: $error')),
        data: (items) {
          final visible = _favoritesOnly ? items.where((i) => i.favorite).toList() : items;
          if (visible.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.folder_open_outlined,
                      size: 40,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _favoritesOnly
                          ? 'Henüz favori işaretlediğin bir şey yok.'
                          : 'Kütüphanen boş. + ile ilk içeriğini ekle.',
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            itemCount: visible.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) => _ItemTile(item: visible[index]),
          );
        },
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item});

  final Item item;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(child: Icon(itemTypeIcon(item.type))),
      title: Text(item.title ?? item.originalFilename ?? 'Untitled', maxLines: 1),
      subtitle: Text(
        '${itemTypeLabel(item.type)} · ${DateFormat('d MMM').format(item.createdAt)}',
      ),
      trailing: item.favorite ? const Icon(Icons.star, size: 20) : null,
      onTap: () {
        final route = item.type == ItemType.note ? '/item/${item.id}/note' : '/item/${item.id}';
        context.push(route, extra: item);
      },
    );
  }
}
