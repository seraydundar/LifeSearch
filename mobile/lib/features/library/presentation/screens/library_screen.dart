import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/extensions/build_context_x.dart';
import '../../../collections/presentation/widgets/collection_suggestions_section.dart';
import '../../../collections/presentation/widgets/collections_bar.dart';
import '../../../item/presentation/providers/item_providers.dart';
import '../../../item/presentation/widgets/item_list_tile.dart';
import '../../../settings/presentation/providers/app_lock_providers.dart';
import '../../domain/library_sort.dart';
import '../providers/library_view_providers.dart';
import '../widgets/item_grid_tile.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  bool _favoritesOnly = false;

  /// Item-level Privacy Mode (Faz 11, madde 2 — see docs/roadmap.md).
  /// Hiding never needs a check; revealing does. `AppLockGate` already
  /// re-hides on backgrounding regardless of how this got turned on.
  Future<void> _togglePrivateReveal() async {
    if (ref.read(privateItemsRevealedProvider)) {
      ref.read(privateItemsRevealedProvider.notifier).state = false;
      return;
    }
    final supported = await ref.read(appLockDeviceSupportedProvider.future);
    if (!mounted) return;
    if (!supported) {
      context.showErrorSnackBar(
        'Private içerikleri görmek için cihazında biyometrik/PIN kilidi ayarlı olmalı.',
      );
      return;
    }
    final authenticated = await ref.read(appLockServiceProvider).authenticate();
    if (!mounted || !authenticated) return;
    ref.read(privateItemsRevealedProvider.notifier).state = true;
  }

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(itemsProvider);
    final viewMode = ref.watch(libraryViewModeProvider);
    final sort = ref.watch(librarySortProvider);
    final privateRevealed = ref.watch(privateItemsRevealedProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        actions: [
          PopupMenuButton<LibrarySort>(
            icon: const Icon(Icons.sort),
            tooltip: 'Sırala',
            initialValue: sort,
            onSelected: (value) => ref.read(librarySortProvider.notifier).state = value,
            itemBuilder: (context) => const [
              PopupMenuItem(value: LibrarySort.newestFirst, child: Text('En yeni')),
              PopupMenuItem(value: LibrarySort.oldestFirst, child: Text('En eski')),
              PopupMenuItem(value: LibrarySort.nameAscending, child: Text('İsme göre (A-Z)')),
              PopupMenuItem(value: LibrarySort.byType, child: Text('Türe göre')),
            ],
          ),
          IconButton(
            icon: Icon(viewMode == LibraryViewMode.list ? Icons.grid_view_outlined : Icons.view_list_outlined),
            tooltip: viewMode == LibraryViewMode.list ? 'Grid görünümü' : 'Liste görünümü',
            onPressed: () => ref.read(libraryViewModeProvider.notifier).state =
                viewMode == LibraryViewMode.list ? LibraryViewMode.grid : LibraryViewMode.list,
          ),
          IconButton(
            icon: Icon(_favoritesOnly ? Icons.star : Icons.star_border),
            tooltip: 'Sadece favoriler',
            onPressed: () => setState(() => _favoritesOnly = !_favoritesOnly),
          ),
          IconButton(
            icon: Icon(privateRevealed ? Icons.lock_open_outlined : Icons.lock_outline),
            tooltip: privateRevealed ? 'Private içerikleri gizle' : 'Private içerikleri göster',
            onPressed: _togglePrivateReveal,
          ),
        ],
      ),
      body: Column(
        children: [
          const CollectionSuggestionsSection(),
          const CollectionsBar(),
          const Divider(height: 1),
          Expanded(
            child: itemsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text('Yüklenemedi: $error')),
              data: (items) {
                final filtered = _favoritesOnly ? items.where((i) => i.favorite).toList() : items;
                final visible = sortItems(filtered, sort);
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
                if (viewMode == LibraryViewMode.grid) {
                  return GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.85,
                    ),
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final item = visible[index];
                      // A stable per-item key, not just position — without
                      // it, Flutter reuses a tile's State by position when
                      // the sorted list reorders (e.g. a new note becomes
                      // newest and pushes everything else down a slot).
                      // ItemGridTile fetches its signed URL once in
                      // initState(), so a reused tile would keep showing
                      // the *previous* occupant's already-resolved
                      // thumbnail under the new item's title.
                      return ItemGridTile(key: ValueKey(item.id), item: item);
                    },
                  );
                }
                return ListView.separated(
                  itemCount: visible.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, index) => ItemListTile(item: visible[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
