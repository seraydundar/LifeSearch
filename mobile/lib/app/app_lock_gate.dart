import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/presentation/providers/auth_providers.dart';
import '../features/item/presentation/providers/item_providers.dart';
import '../features/settings/presentation/providers/app_lock_providers.dart';
import '../features/settings/presentation/screens/app_lock_screen.dart';

/// Replaces (not overlays) the app's UI with a lock screen when app-lock is enabled and unused.
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Use `paused`, not `inactive` — `inactive` also fires for transient system UI (share sheet, etc).
    if (state == AppLifecycleState.paused) {
      final enabled = ref.read(appLockEnabledProvider).valueOrNull ?? false;
      if (enabled) ref.read(appLockUnlockedProvider.notifier).state = false;
      // Re-hides regardless of whole-app lock state.
      ref.read(privateItemsRevealedProvider.notifier).state = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Re-hide on account change too, not just backgrounding, so a new sign-in can't inherit it.
    ref.listen(currentUserIdProvider, (previous, next) {
      if (previous != next) {
        ref.read(privateItemsRevealedProvider.notifier).state = false;
      }
    });

    final enabled = ref.watch(appLockEnabledProvider).valueOrNull ?? false;
    final unlocked = ref.watch(appLockUnlockedProvider);

    if (enabled && !unlocked) {
      return const AppLockScreen();
    }
    return widget.child;
  }
}
