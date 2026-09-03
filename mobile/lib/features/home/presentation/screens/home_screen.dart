import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../capture/presentation/widgets/capture_sheet.dart';
import '../../../item/domain/entities/item.dart';
import '../../../item/presentation/providers/item_providers.dart';
import '../../../item/presentation/widgets/item_type_icon.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final itemsAsync = ref.watch(itemsProvider);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('Good morning 👋', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 20),
            TextField(
              readOnly: true, // typing happens on the dedicated Search screen
              onTap: () => context.push('/search'),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search your life...',
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 32),
            Text('Recently Added', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            itemsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Text('Yüklenemedi: $error'),
              data: (items) => items.isEmpty
                  ? const _EmptyStateCard(
                      icon: Icons.inbox_outlined,
                      message: 'Henüz içerik eklemedin.\n+ ile ilk içeriğini ekle.',
                    )
                  : SizedBox(
                      height: 96,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: items.length > 10 ? 10 : items.length,
                        separatorBuilder: (context, index) => const SizedBox(width: 12),
                        itemBuilder: (context, index) => _RecentCard(item: items[index]),
                      ),
                    ),
            ),
            const SizedBox(height: 32),
            Text('Your Library', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            itemsAsync.maybeWhen(
              data: (items) => Column(
                children: [
                  _LibraryRow(
                    icon: Icons.image_outlined,
                    label: 'Images',
                    count: items
                        .where((i) => i.type == ItemType.image || i.type == ItemType.screenshot)
                        .length,
                  ),
                  _LibraryRow(
                    icon: Icons.description_outlined,
                    label: 'Documents',
                    count: items
                        .where((i) => i.type == ItemType.pdf || i.type == ItemType.document)
                        .length,
                  ),
                  _LibraryRow(
                    icon: Icons.notes_outlined,
                    label: 'Notes',
                    count: items.where((i) => i.type == ItemType.note).length,
                  ),
                  _LibraryRow(
                    icon: Icons.link,
                    label: 'Links',
                    count: items.where((i) => i.type == ItemType.url).length,
                  ),
                ],
              ),
              orElse: () => const SizedBox.shrink(),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showCaptureSheet(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _RecentCard extends StatelessWidget {
  const _RecentCard({required this.item});

  final Item item;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        final route = item.type == ItemType.note ? '/item/${item.id}/note' : '/item/${item.id}';
        context.push(route, extra: item);
      },
      child: Container(
        width: 120,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(itemTypeIcon(item.type), size: 20),
            const Spacer(),
            Text(
              item.title ?? item.originalFilename ?? 'Untitled',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyStateCard extends StatelessWidget {
  const _EmptyStateCard({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(icon, size: 32, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _LibraryRow extends StatelessWidget {
  const _LibraryRow({required this.icon, required this.label, required this.count});

  final IconData icon;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyLarge)),
          Text('$count', style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    );
  }
}
