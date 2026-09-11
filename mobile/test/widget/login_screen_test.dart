import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesearch/core/error/failure.dart';
import 'package:lifesearch/features/auth/presentation/providers/auth_providers.dart';
import 'package:lifesearch/features/auth/presentation/screens/login_screen.dart';

import '../fakes/fake_auth_repository.dart';
import '../fakes/fake_native_oauth_service.dart';

void main() {
  Widget wrap(
    FakeAuthRepository repo, {
    FakeNativeOAuthService? oauth,
    bool googleAvailable = false,
    bool appleAvailable = false,
  }) {
    return ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(repo),
        nativeOAuthServiceProvider.overrideWithValue(oauth ?? FakeNativeOAuthService()),
        googleSignInAvailableProvider.overrideWithValue(googleAvailable),
        appleSignInAvailableProvider.overrideWithValue(appleAvailable),
      ],
      child: MaterialApp(home: const LoginScreen()),
    );
  }

  testWidgets('shows email and password fields and a submit button', (tester) async {
    await tester.pumpWidget(wrap(FakeAuthRepository()));

    expect(find.text('E-posta'), findsOneWidget);
    expect(find.text('Şifre'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Giriş Yap'), findsOneWidget);
  });

  testWidgets('shows validation errors when submitting empty form', (tester) async {
    await tester.pumpWidget(wrap(FakeAuthRepository()));

    await tester.tap(find.widgetWithText(ElevatedButton, 'Giriş Yap'));
    await tester.pump();

    expect(find.text('Geçerli bir e-posta gir'), findsOneWidget);
    expect(find.text('Şifre en az 6 karakter olmalı'), findsOneWidget);
  });

  testWidgets('signs in and updates authControllerProvider state', (tester) async {
    final repo = FakeAuthRepository();
    final container = ProviderContainer(
      overrides: [authRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: const LoginScreen()),
      ),
    );

    await tester.enterText(find.byType(TextFormField).first, 'user@example.com');
    await tester.enterText(find.byType(TextFormField).last, 'password123');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Giriş Yap'));
    await tester.pumpAndSettle();

    final state = container.read(authControllerProvider);
    expect(state.value?.email, 'user@example.com');
  });

  testWidgets('neither Google nor Apple button shows when unavailable', (tester) async {
    await tester.pumpWidget(wrap(FakeAuthRepository()));

    expect(find.text('Google ile devam et'), findsNothing);
    expect(find.text('Apple ile devam et'), findsNothing);
    expect(find.text('veya'), findsNothing); // the divider has nothing to divide
  });

  testWidgets('tapping Google signs in with the token from the native picker',
      (tester) async {
    final repo = FakeAuthRepository();
    final oauth = FakeNativeOAuthService(googleIdToken: 'real-looking-id-token');
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(repo),
        nativeOAuthServiceProvider.overrideWithValue(oauth),
        googleSignInAvailableProvider.overrideWithValue(true),
        appleSignInAvailableProvider.overrideWithValue(false),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: const LoginScreen()),
      ),
    );

    await tester.tap(find.text('Google ile devam et'));
    await tester.pumpAndSettle();

    expect(oauth.signInWithGoogleCallCount, 1);
    expect(repo.lastGoogleIdToken, 'real-looking-id-token');
    expect(container.read(authControllerProvider).value?.email, 'google-user@example.com');
  });

  testWidgets('tapping Apple signs in with the token from the native picker', (tester) async {
    final repo = FakeAuthRepository();
    final oauth = FakeNativeOAuthService(appleIdToken: 'real-looking-apple-token');
    await tester.pumpWidget(wrap(repo, oauth: oauth, appleAvailable: true));

    await tester.tap(find.text('Apple ile devam et'));
    await tester.pumpAndSettle();

    expect(oauth.signInWithAppleCallCount, 1);
    expect(repo.lastAppleIdToken, 'real-looking-apple-token');
  });

  testWidgets('cancelling the native Google picker leaves the user signed out, no error',
      (tester) async {
    final repo = FakeAuthRepository();
    final oauth = FakeNativeOAuthService(googleIdToken: null); // cancelled
    await tester.pumpWidget(wrap(repo, oauth: oauth, googleAvailable: true));

    await tester.tap(find.text('Google ile devam et'));
    await tester.pumpAndSettle();

    expect(repo.lastGoogleIdToken, isNull); // AuthRepository never even called
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a native sign-in failure surfaces as an error snackbar, not a crash',
      (tester) async {
    final repo = FakeAuthRepository();
    final oauth = FakeNativeOAuthService()
      ..errorToThrow = const AuthFailure('Google ile giriş yapılamadı: network error');
    await tester.pumpWidget(wrap(repo, oauth: oauth, googleAvailable: true));

    await tester.tap(find.text('Google ile devam et'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Google ile giriş yapılamadı'), findsOneWidget);
  });
}
