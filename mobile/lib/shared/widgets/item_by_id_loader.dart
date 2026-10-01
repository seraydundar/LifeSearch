import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/item/domain/entities/item.dart';
import '../../features/item/presentation/providers/item_providers.dart';

/// Resolves an [Item] by id for routes reached without `state.extra` (deep link, push
/// notification, or route restore after process death) via the local cache.
class ItemByIdLoader extends ConsumerWidget {
  const ItemByIdLoader({super.key, required this.itemId, required this.builder});

  final String itemId;
  final Widget Function(Item item) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(itemByIdProvider(itemId));
    // Same private-item gate as Home/Library/Search, since this path bypasses their filtering.
    final revealed = ref.watch(privateItemsRevealedProvider);
    return item.when(
      data: (item) {
        if (item == null) return const _ItemNotFound();
        if (item.private && !revealed) return const _ItemNotFound();
        return builder(item);
      },
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, _) => const _ItemNotFound(),
    );
  }
}

class _ItemNotFound extends StatelessWidget {
  const _ItemNotFound();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'İçerik bulunamadı. Henüz bu cihazla senkronize olmamış '
            'olabilir — bağlantın varsa birazdan tekrar dene.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
