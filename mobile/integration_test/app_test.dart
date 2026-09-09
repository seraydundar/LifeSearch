// True end-to-end tests: unlike the widget tests in test/widget/, these
// pump the real `LifeSearchApp` (real go_router, real screen wiring, real
// rendering pipeline) on an actual device/simulator via the
// `integration_test` package, rather than an individual screen wrapped in
// a bespoke test harness. Only the boundary that talks to Supabase/the
// backend is faked — auth, item storage, collections, app-lock — so these
// never touch the network, but everything above that boundary (routing,
// providers, real widgets, real gestures) is exercised as a whole.
//
// Run with a device attached/booted:
//   flutter test integration_test/app_test.dart -d <device-id>
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lifesearch/app/app.dart';
import 'package:lifesearch/core/network/api_client_provider.dart';
import 'package:lifesearch/features/auth/domain/entities/app_user.dart';
import 'package:lifesearch/features/auth/presentation/providers/auth_providers.dart';
import 'package:lifesearch/features/collections/presentation/providers/collection_providers.dart';
import 'package:lifesearch/features/collections/presentation/providers/collection_suggestion_providers.dart';
import 'package:lifesearch/features/item/presentation/providers/item_providers.dart';
import 'package:lifesearch/features/settings/presentation/providers/app_lock_providers.dart';

import '../test/fakes/fake_app_lock_service.dart';
import '../test/fakes/fake_auth_repository.dart';
import '../test/fakes/fake_collection_repository.dart';
import '../test/fakes/fake_collection_suggestion_repository.dart';
import '../test/fakes/fake_item_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// The full set of overrides every scenario below needs just to keep the
  /// app out of real Supabase/backend/plugin territory — everything else
  /// (routing, provider wiring, real screens) is the genuine app.
  List<Override> baseOverrides({
    FakeAuthRepository? auth,
    FakeItemRepository? items,
    FakeAppLockService? appLock,
  }) {
    return [
      authRepositoryProvider.overrideWithValue(
        auth ?? FakeAuthRepository(initialUser: const AppUser(id: 'u1', email: 'test@example.com')),
      ),
      itemRepositoryProvider.overrideWithValue(items ?? FakeItemRepository()),
      collectionRepositoryProvider.overrideWithValue(FakeCollectionRepository()),
      collectionSuggestionRepositoryProvider.overrideWithValue(FakeCollectionSuggestionRepository()),
      apiClientProvider.overrideWithValue(null),
      pendingSyncCountProvider.overrideWith((ref) => Stream.value(0)),
      appLockServiceProvider.overrideWithValue(appLock ?? FakeAppLockService(deviceSupported: false)),
    ];
  }

  testWidgets('signed-out users see the login screen, not the app', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: baseOverrides(auth: FakeAuthRepository(initialUser: null)),
      child: const LifeSearchApp(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('E-posta'), findsOneWidget);
    expect(find.text('Şifre'), findsOneWidget);
    expect(find.text('Giriş Yap'), findsOneWidget);
  });

  testWidgets('the bottom nav switches between Home, Library, and Settings', (tester) async {
    await tester.pumpWidget(ProviderScope(overrides: baseOverrides(), child: const LifeSearchApp()));
    await tester.pumpAndSettle();

    // Home is the initial route.
    expect(find.text('Good morning 👋'), findsOneWidget);

    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();
    expect(find.text('Kütüphanen boş. + ile ilk içeriğini ekle.'), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('test@example.com'), findsOneWidget);

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.text('Good morning 👋'), findsOneWidget);
  });

  testWidgets(
    'creating a note from Home shows up in Library immediately, with no manual refresh',
    (tester) async {
      await tester.pumpWidget(ProviderScope(overrides: baseOverrides(), child: const LifeSearchApp()));
      await tester.pumpAndSettle();

      // Home → "+" → "Create Note".
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create Note'));
      await tester.pumpAndSettle();

      // The note editor has exactly two TextFields in create mode (no
      // TagsRow, which only appears once an item exists) — title, then
      // content.
      await tester.enterText(find.byType(TextField).first, 'Entegrasyon testi notu');
      await tester.tap(find.byIcon(Icons.check));
      await tester.pumpAndSettle();

      // Saving pops back to Home.
      expect(find.text('Good morning 👋'), findsOneWidget);

      await tester.tap(find.text('Library'));
      await tester.pumpAndSettle();

      expect(find.text('Entegrasyon testi notu'), findsOneWidget);
    },
  );

  group('app lock', () {
    testWidgets('blocks the app until the user authenticates', (tester) async {
      final appLock = FakeAppLockService(initiallyEnabled: true, authenticateResult: false);
      await tester.pumpWidget(ProviderScope(
        overrides: baseOverrides(appLock: appLock),
        child: const LifeSearchApp(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('LifeSearch kilitli'), findsOneWidget);
      expect(find.text('Good morning 👋'), findsNothing);
    });

    testWidgets('reveals the app after a successful authentication', (tester) async {
      final appLock = FakeAppLockService(initiallyEnabled: true, authenticateResult: true);
      await tester.pumpWidget(ProviderScope(
        overrides: baseOverrides(appLock: appLock),
        child: const LifeSearchApp(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('LifeSearch kilitli'), findsNothing);
      expect(find.text('Good morning 👋'), findsOneWidget);
    });
  });
}
