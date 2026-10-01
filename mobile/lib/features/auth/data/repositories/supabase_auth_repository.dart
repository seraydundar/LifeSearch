import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/error/failure.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/repositories/auth_repository.dart';

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client);

  final SupabaseClient _client;

  AppUser? _toAppUser(User? user) {
    if (user == null || user.email == null) return null;
    return AppUser(id: user.id, email: user.email!);
  }

  @override
  Stream<AppUser?> authStateChanges() {
    return _client.auth.onAuthStateChange.map((data) => _toAppUser(data.session?.user));
  }

  @override
  AppUser? get currentUser => _toAppUser(_client.auth.currentUser);

  @override
  Future<AppUser> signIn({required String email, required String password}) async {
    try {
      final response = await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      final user = _toAppUser(response.user);
      if (user == null) {
        throw const AuthFailure('Giriş başarısız oldu. Lütfen tekrar deneyin.');
      }
      return user;
    } on AuthException catch (e) {
      throw AuthFailure(_mapAuthError(e));
    }
  }

  @override
  Future<AppUser> signUp({required String email, required String password}) async {
    try {
      final response = await _client.auth.signUp(email: email, password: password);
      if (response.session == null) {
        // `user` is set even when email confirmation is pending; `session` is the real signal.
        throw const AuthFailure(
          'Hesap oluşturuldu. Devam etmeden önce lütfen e-postanı onayla.',
        );
      }
      final user = _toAppUser(response.user);
      if (user == null) {
        throw const AuthFailure('Kayıt başarısız oldu. Lütfen tekrar deneyin.');
      }
      return user;
    } on AuthException catch (e) {
      throw AuthFailure(_mapAuthError(e));
    }
  }

  @override
  Future<AppUser> signInWithGoogleIdToken({required String idToken}) async {
    try {
      final response = await _client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
      );
      final user = _toAppUser(response.user);
      if (user == null) {
        throw const AuthFailure('Google ile giriş başarısız oldu. Lütfen tekrar dene.');
      }
      return user;
    } on AuthException catch (e) {
      throw AuthFailure(_mapAuthError(e));
    }
  }

  @override
  Future<AppUser> signInWithAppleIdToken({required String idToken}) async {
    try {
      final response = await _client.auth.signInWithIdToken(
        provider: OAuthProvider.apple,
        idToken: idToken,
      );
      final user = _toAppUser(response.user);
      if (user == null) {
        throw const AuthFailure('Apple ile giriş başarısız oldu. Lütfen tekrar dene.');
      }
      return user;
    } on AuthException catch (e) {
      throw AuthFailure(_mapAuthError(e));
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } on AuthException catch (e) {
      throw AuthFailure(_mapAuthError(e));
    }
  }

  String _mapAuthError(AuthException e) {
    switch (e.message.toLowerCase()) {
      case final m when m.contains('invalid login credentials'):
        return 'E-posta veya şifre hatalı.';
      case final m when m.contains('user already registered'):
        return 'Bu e-posta ile zaten bir hesap var.';
      case final m when m.contains('password should be at least'):
        return 'Şifre en az 6 karakter olmalı.';
      default:
        return e.message;
    }
  }
}
