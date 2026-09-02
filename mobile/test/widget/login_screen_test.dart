import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesearch/features/auth/presentation/providers/auth_providers.dart';
import 'package:lifesearch/features/auth/presentation/screens/login_screen.dart';

import '../fakes/fake_auth_repository.dart';

void main() {
  Widget wrap(FakeAuthRepository repo) {
    return ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(repo)],
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
}
