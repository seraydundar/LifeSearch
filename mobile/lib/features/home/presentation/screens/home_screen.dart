import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/widgets/life_search_bar.dart';
import '../../../capture/presentation/widgets/capture_sheet.dart';
import '../../../item/domain/entities/item.dart';
import '../../../item/presentation/providers/item_providers.dart';
import '../../../library/presentation/widgets/item_grid_tile.dart';

/// The Home greeting's time-of-day text — a plain function (not inline
/// in `build`) so it's unit-testable without needing to fake
/// `DateTime.now()` through a whole widget pump. Boundaries follow the
/// common "before noon / before 6pm / else" convention; the device's
/// own wall-clock hour, not anything synced or configurable.
String greetingForHour(int hour) {
  if (hour < 12) return 'Good morning';
  if (hour < 18) return 'Good afternoon';
  return 'Good evening';
}

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
            Text(
              '${greetingForHour(DateTime.now().hour)} 👋',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 20),
            LifeSearchBar(
              readOnly: true, // typing happens on the dedicated Search screen
              onTap: () => context.push('/search'),
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
                      height: 120,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: items.length > 10 ? 10 : items.length,
                        separatorBuilder: (context, index) => const SizedBox(width: 12),
                        // Same tile Library's grid uses (requirements doc,
                        // section 25) — real thumbnail for images/
                        // screenshots, type icon + title fallback for
                        // everything else, so Home's teaser matches what
                        // the user actually sees once they tap in.
                        itemBuilder: (context, index) => SizedBox(
                          width: 120,
                          child: ItemGridTile(item: items[index]),
                        ),
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
