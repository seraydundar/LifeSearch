import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesearch/app/app_lock_gate.dart';
import 'package:lifesearch/features/auth/domain/entities/app_user.dart';
import 'package:lifesearch/features/auth/presentation/providers/auth_providers.dart';
import 'package:lifesearch/features/item/presentation/providers/item_providers.dart';
import 'package:lifesearch/features/settings/presentation/providers/app_lock_providers.dart';

import '../fakes/fake_app_lock_service.dart';

void main() {
  Widget wrap(FakeAppLockService appLock, {List<Override> extraOverrides = const []}) {
    return ProviderScope(
      overrides: [
        appLockServiceProvider.overrideWithValue(appLock),
        ...extraOverrides,
      ],
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

  testWidgets(
      // P1-01 (docs/requirements-audit-2026-09-13.md): private reveal used
      // to survive a sign-out/sign-in inside the same app session, the
      // same gap `AppLockGate`'s backgrounding re-lock already covered
      // for a background/foreground cycle — a different account on the
      // same device inherited the previous one's unlocked private view.
      'switching accounts re-hides already-revealed private items',
      (tester) async {
    final auth = StreamController<AppUser?>();
    addTearDown(auth.close);
    final appLock = FakeAppLockService(initiallyEnabled: false);

    late ProviderContainer container;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appLockServiceProvider.overrideWithValue(appLock),
        authStateChangesProvider.overrideWith((ref) => auth.stream),
      ],
      child: Consumer(builder: (context, ref, _) {
        container = ProviderScope.containerOf(context);
        return MaterialApp(
          home: AppLockGate(child: const Scaffold(body: Text('home'))),
        );
      }),
    ));
    await tester.pumpAndSettle();

    auth.add(const AppUser(id: 'user-a', email: 'a@example.com'));
    await tester.pump();
    container.read(privateItemsRevealedProvider.notifier).state = true;
    expect(container.read(privateItemsRevealedProvider), isTrue);

    auth.add(const AppUser(id: 'user-b', email: 'b@example.com'));
    await tester.pump();

    expect(container.read(privateItemsRevealedProvider), isFalse);
  });
}
