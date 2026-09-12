import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../../core/error/failure.dart';

/// Wraps the native Google/Apple sign-in SDKs (Faz 11, madde 5 — see
/// docs/roadmap.md) so `AuthController` never touches `google_sign_in`/
/// `sign_in_with_apple` directly — the same reason `AppLockService`
/// wraps `local_auth`: an overridable class a test can fake without
/// ever hitting a real platform channel.
///
/// Neither provider works without real external setup this app can't
/// do on its own — a Google Cloud Console OAuth client + a matching
/// Supabase "Google" provider entry, or an Apple Developer "Sign in
/// with Apple" capability + Services ID + a matching Supabase "Apple"
/// provider entry. See docs/google-apple-login-setup.md for the full
/// checklist; `LoginScreen` hides each button until its own prerequisite
/// is met, rather than showing one that would just fail.
class NativeOAuthService {
  /// Apple Sign In only on iOS/macOS — an Android build would need a
  /// separate web-based flow (`webAuthenticationOptions`, a Services ID
  /// with its own redirect URI) that isn't set up here; see
  /// docs/google-apple-login-setup.md.
  bool get isAppleAvailable => !kIsWeb && (Platform.isIOS || Platform.isMacOS);

  /// `google_sign_in`'s web implementation deliberately doesn't support
  /// [signInWithGoogle]'s imperative `authenticate()` call at all — it
  /// throws `UnsupportedError`, directing callers to `renderButton()`
  /// instead (a Google-controlled button rendered into the DOM, a
  /// fundamentally different flow this app doesn't implement). This was
  /// previously only gated on whether `GOOGLE_CLIENT_ID`/
  /// `GOOGLE_SERVER_CLIENT_ID` were configured — on web, configuring
  /// them was enough to show a button that would then always throw the
  /// moment it was tapped (Faz 12, madde 11, denetim düzeltmesi — see
  /// docs/roadmap.md). Checking the plugin's own advertised capability
  /// (rather than hardcoding `!kIsWeb`) means this also stays correct
  /// on any future platform the package adds or drops support for,
  /// without needing a matching code change here.
  ///
  /// Guarded like `AppLockService.isDeviceSupported()`: a platform with
  /// no registered `google_sign_in` implementation at all (Windows/
  /// Linux — not a target today, see docs/roadmap.md, but a real gap in
  /// this package specifically) throws rather than returning `false`,
  /// same as a bare test binary that never registers one — either way,
  /// "can't tell" is treated the same as "not available", not a crash.
  bool get isGoogleAvailable {
    try {
      return GoogleSignIn.instance.supportsAuthenticate();
    } catch (_) {
      // Deliberately a bare catch, not `on Exception` (the convention
      // elsewhere in this class/`AppLockService`): the placeholder
      // implementation `google_sign_in_platform_interface` falls back
      // to when nothing has registered a real one throws
      // `UnimplementedError`, which is an `Error`, not an `Exception`.
      return false;
    }
  }

  /// The Google ID token to hand to
  /// `AuthRepository.signInWithGoogleIdToken`, or `null` if the user
  /// cancelled the native account picker — not an error (see
  /// `AuthController.signInWithGoogle`).
  Future<String?> signInWithGoogle() async {
    try {
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        // Shouldn't happen in practice — `authenticate()` only completes
        // once the account is actually authenticated — but a null token
        // is still a clearer failure than a null check exception deeper
        // in `signInWithGoogleIdToken`.
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
