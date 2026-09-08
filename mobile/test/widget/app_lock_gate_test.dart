import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesearch/app/app_lock_gate.dart';
import 'package:lifesearch/features/settings/presentation/providers/app_lock_providers.dart';

import '../fakes/fake_app_lock_service.dart';

void main() {
  Widget wrap(FakeAppLockService appLock) {
    return ProviderScope(
      overrides: [appLockServiceProvider.overrideWithValue(appLock)],
      child: MaterialApp(
        home: AppLockGate(child: const Scaffold(body: Text('home'))),
      ),
    );
  }

  testWidgets('shows the app straight away when app-lock is off', (tester) async {
    await tester.pumpWidget(wrap(FakeAppLockService(initiallyEnabled: false)));
    await tester.pumpAndSettle();

    expect(find.text('home'), findsOneWidget);
    expect(find.text('LifeSearch kilitli'), findsNothing);
  });

  testWidgets('shows the lock screen instead of the app when enabled and locked',
      (tester) async {
    final appLock = FakeAppLockService(initiallyEnabled: true, authenticateResult: false);
    await tester.pumpWidget(wrap(appLock));
    await tester.pumpAndSettle();

    expect(find.text('LifeSearch kilitli'), findsOneWidget);
    expect(find.text('home'), findsNothing);
    // Prompts automatically, without waiting for a tap.
    expect(appLock.authenticateCallCount, 1);
  });

  testWidgets('a successful authentication reveals the app', (tester) async {
    final appLock = FakeAppLockService(initiallyEnabled: true, authenticateResult: true);
    await tester.pumpWidget(wrap(appLock));
    await tester.pumpAndSettle();

    expect(find.text('home'), findsOneWidget);
    expect(find.text('LifeSearch kilitli'), findsNothing);
  });

  testWidgets('backgrounding the app re-locks it', (tester) async {
    final appLock = FakeAppLockService(initiallyEnabled: true, authenticateResult: true);
    await tester.pumpWidget(wrap(appLock));
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    // `paused` (like `hidden`/`detached`) disables the test binding's frame
    // pumping altogether — matching real "app is backgrounded" behavior.
    // Switching straight back to `resumed` re-enables frames so the
    // rebuild triggered by the `paused` transition above can actually be
    // observed; `AppLockGate` itself only reacts to `paused`, not
    // `resumed`, so this doesn't undo the re-lock.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    // One frame only — before the freshly-mounted lock screen's own
    // auto-authenticate (which would immediately succeed again) resolves.
    await tester.pump();

    expect(find.text('LifeSearch kilitli'), findsOneWidget);
    expect(find.text('home'), findsNothing);
  });

  testWidgets('a merely transient (inactive) state does not re-lock', (tester) async {
    final appLock = FakeAppLockService(initiallyEnabled: true, authenticateResult: true);
    await tester.pumpWidget(wrap(appLock));
    await tester.pumpAndSettle();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();

    expect(find.text('home'), findsOneWidget);
    expect(appLock.authenticateCallCount, 1);
  });
}
