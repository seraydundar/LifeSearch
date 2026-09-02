import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesearch/core/error/failure.dart';
import 'package:lifesearch/features/auth/presentation/providers/auth_providers.dart';

import '../fakes/fake_auth_repository.dart';

void main() {
  late FakeAuthRepository repository;
  late ProviderContainer container;

  setUp(() {
    repository = FakeAuthRepository();
    container = ProviderContainer(
      overrides: [authRepositoryProvider.overrideWithValue(repository)],
    );
  });

  tearDown(() {
    container.dispose();
    repository.dispose();
  });

  test('starts signed out when the repository has no current user', () {
    final state = container.read(authControllerProvider);
    expect(state.value, isNull);
  });

  test('signIn success updates state with the signed-in user', () async {
    final controller = container.read(authControllerProvider.notifier);

    await controller.signIn(email: 'user@example.com', password: 'password123');

    final state = container.read(authControllerProvider);
    expect(state.value?.email, 'user@example.com');
    expect(state.hasError, isFalse);
  });

  test('signIn failure surfaces as AsyncError, not a thrown exception', () async {
    repository.failureToThrow = const AuthFailure('E-posta veya şifre hatalı.');
    final controller = container.read(authControllerProvider.notifier);

    await controller.signIn(email: 'user@example.com', password: 'wrong');

    final state = container.read(authControllerProvider);
    expect(state.hasError, isTrue);
    expect(state.error, isA<AuthFailure>());
  });

  test('signOut clears the current user', () async {
    final controller = container.read(authControllerProvider.notifier);
    await controller.signIn(email: 'user@example.com', password: 'password123');

    await controller.signOut();

    final state = container.read(authControllerProvider);
    expect(state.value, isNull);
    expect(state.hasError, isFalse);
  });
}
