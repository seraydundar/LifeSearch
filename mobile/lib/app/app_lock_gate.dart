import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/presentation/providers/auth_providers.dart';
import '../features/item/presentation/providers/item_providers.dart';
import '../features/settings/presentation/providers/app_lock_providers.dart';
import '../features/settings/presentation/screens/app_lock_screen.dart';

/// Wraps the whole app (via `MaterialApp.router`'s `builder`) and shows a
/// full-screen lock overlay — in place of, not on top of, the app's actual
/// UI — whenever app-lock is enabled and the current session hasn't been
/// unlocked yet. That happens on cold start, and again every time the app
/// returns from the background.
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
    // `inactive` also fires for transient system UI (share sheet,
    // notification shade, an incoming call banner) — only re-lock once the
    // app has actually been backgrounded, not on every brief interruption.
    if (state == AppLifecycleState.paused) {
      final enabled = ref.read(appLockEnabledProvider).valueOrNull ?? false;
      if (enabled) ref.read(appLockUnlockedProvider.notifier).state = false;
      // Item-level Privacy Mode (Faz 11, madde 2) re-hides itself on
      // backgrounding independently of whether the whole-app lock is even
      // turned on — a private item revealed a moment ago shouldn't still
      // be visible after the app comes back from the background.
      ref.read(privateItemsRevealedProvider.notifier).state = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // P1-01 (docs/requirements-audit-2026-09-13.md): private reveal used
    // to survive a sign-out/sign-in inside the same app session — the
    // next account could inherit the previous one's unlocked private
    // view until the app happened to be backgrounded. Any account change
    // re-hides private items, the same as backgrounding already does.
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
