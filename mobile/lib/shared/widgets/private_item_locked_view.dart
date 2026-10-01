import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/item/presentation/providers/item_providers.dart';
import '../../features/settings/presentation/providers/app_lock_providers.dart';
import '../extensions/build_context_x.dart';

/// Shown instead of an item's detail/note editor screen once that item is private and reveal has
/// turned back off (e.g. the app was backgrounded with the screen still open). Same reveal flow as
/// `LibraryScreen`'s reveal button.
class PrivateItemLockedView extends ConsumerWidget {
  const PrivateItemLockedView({super.key});

  Future<void> _reveal(BuildContext context, WidgetRef ref) async {
    final supported = await ref.read(appLockDeviceSupportedProvider.future);
    if (!context.mounted) return;
    if (!supported) {
      context.showErrorSnackBar(
        'Private içerikleri görmek için cihazında biyometrik/PIN kilidi ayarlı olmalı.',
      );
      return;
    }
    final authenticated = await ref.read(appLockServiceProvider).authenticate();
    if (!context.mounted || !authenticated) return;
    ref.read(privateItemsRevealedProvider.notifier).state = true;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 48),
              const SizedBox(height: 16),
              const Text(
                'Bu içerik private olarak işaretli.',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text(
                'Görmek için kilidi tekrar aç.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => _reveal(context, ref),
                icon: const Icon(Icons.lock_open_outlined),
                label: const Text('Kilidi Aç'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
