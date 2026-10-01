import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../../core/error/failure.dart';

/// Wraps the native Google/Apple sign-in SDKs so tests can fake them.
class NativeOAuthService {
  /// Android would need a separate web-based flow, not set up here.
  bool get isAppleAvailable => !kIsWeb && (Platform.isIOS || Platform.isMacOS);

  /// `google_sign_in`'s web impl throws `UnsupportedError` on `authenticate()`, so check capability instead of hardcoding `!kIsWeb`.
  bool get isGoogleAvailable {
    try {
      return GoogleSignIn.instance.supportsAuthenticate();
    } catch (_) {
      // Bare catch: an unregistered platform impl throws UnimplementedError (an Error, not Exception).
      return false;
    }
  }

  /// Null if the user cancelled the native picker — not an error.
  Future<String?> signInWithGoogle() async {
    try {
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        throw const AuthFailure('Google kimlik doğrulaması bir ID token döndürmedi.');
      }
      return idToken;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      throw AuthFailure('Google ile giriş yapılamadı: ${e.description ?? e.code}');
    }
  }

  /// Same contract as [signInWithGoogle], for Apple's identity token.
  Future<String?> signInWithApple() async {
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
      );
      final idToken = credential.identityToken;
      if (idToken == null) {
        throw const AuthFailure('Apple kimlik doğrulaması bir ID token döndürmedi.');
      }
      return idToken;
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) return null;
      throw AuthFailure('Apple ile giriş yapılamadı: ${e.message}');
    }
  }
}
