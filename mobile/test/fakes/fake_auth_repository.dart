import 'dart:async';

import 'package:lifesearch/core/error/failure.dart';
import 'package:lifesearch/features/auth/domain/entities/app_user.dart';
import 'package:lifesearch/features/auth/domain/repositories/auth_repository.dart';

/// In-memory `AuthRepository` used by widget/unit tests so they never touch
/// the real Supabase SDK.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({AppUser? initialUser}) : _user = initialUser;

  AppUser? _user;
  final _controller = StreamController<AppUser?>.broadcast();

  /// Set to make the next `signIn`/`signUp` call throw this instead of
  /// succeeding.
  Failure? failureToThrow;

  @override
  AppUser? get currentUser => _user;

  @override
  Stream<AppUser?> authStateChanges() => _controller.stream;

  @override
  Future<AppUser> signIn({required String email, required String password}) async {
    if (failureToThrow case final failure?) throw failure;
    final user = AppUser(id: 'test-user-id', email: email);
    _user = user;
    _controller.add(user);
    return user;
  }

  @override
  Future<AppUser> signUp({required String email, required String password}) =>
      signIn(email: email, password: password);

  String? lastGoogleIdToken;

  @override
  Future<AppUser> signInWithGoogleIdToken({required String idToken}) async {
    lastGoogleIdToken = idToken;
    if (failureToThrow case final failure?) throw failure;
    final user = AppUser(id: 'test-google-user-id', email: 'google-user@example.com');
    _user = user;
    _controller.add(user);
    return user;
  }

  String? lastAppleIdToken;

  @override
  Future<AppUser> signInWithAppleIdToken({required String idToken}) async {
    lastAppleIdToken = idToken;
    if (failureToThrow case final failure?) throw failure;
    final user = AppUser(id: 'test-apple-user-id', email: 'apple-user@example.com');
    _user = user;
    _controller.add(user);
    return user;
  }

  @override
  Future<void> signOut() async {
    _user = null;
    _controller.add(null);
  }

  void dispose() => _controller.close();
}
