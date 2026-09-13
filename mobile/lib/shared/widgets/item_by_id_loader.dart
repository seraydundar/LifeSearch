import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/item/domain/entities/item.dart';
import '../../features/item/presentation/providers/item_providers.dart';

/// Resolves an [Item] by id before handing it to [builder] — the fallback
/// path for routes that normally receive a full [Item] straight from
/// `state.extra` (a fast, in-memory hand-off from whichever screen pushed
/// the route; see app_router.dart's `/item/:id` and `/item/:id/note`).
///
/// `extra` only exists when the route was reached by an in-app tap — a
/// deep link, a push notification, or an Android/iOS route restore after
/// process death never carries one. Casting a missing `extra` straight to
/// `Item` used to crash outright in that case; this resolves the item from
/// its id instead, via the local cache (`ItemRepository.findById` —
/// nothing here calls the network directly).
class ItemByIdLoader extends ConsumerWidget {
  const ItemByIdLoader({super.key, required this.itemId, required this.builder});

  final String itemId;
  final Widget Function(Item item) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(itemByIdProvider(itemId));
    // P1-02 (docs/requirements-audit-2026-09-13.md): this was a second,
    // unguarded way to reach a private item's detail screen — a deep
    // link, a push notification, or an Android/iOS route restore never
    // goes through Home/Library/Search's own private filtering, so it
    // resolved and rendered a private item unconditionally, reveal or
    // not. Same gate as everywhere else: revealed, or not private.
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
