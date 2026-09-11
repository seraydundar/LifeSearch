import '../entities/app_user.dart';

/// Contract the presentation layer codes against. `features/auth/data`
/// provides the Supabase-backed implementation; tests can provide a fake
/// one instead — the UI never knows which.
abstract interface class AuthRepository {
  /// The current user, or `null` if signed out. Emits again on every
  /// sign-in/sign-out/session-refresh — this is what the router listens to
  /// for redirect decisions.
  Stream<AppUser?> authStateChanges();

  AppUser? get currentUser;

  Future<AppUser> signIn({required String email, required String password});

  Future<AppUser> signUp({required String email, required String password});

  /// Exchanges a Google ID token (already obtained from the native
  /// Google Sign-In SDK — see `NativeOAuthService`) for a Supabase
  /// session (Faz 11, madde 5 — see docs/roadmap.md). Works for both a
  /// brand-new user and one signing back in; Supabase creates the
  /// account automatically on first use, same as it does for
  /// email/password `signUp`.
  Future<AppUser> signInWithGoogleIdToken({required String idToken});

  /// Same contract as [signInWithGoogleIdToken], for Apple's identity
  /// token.
  Future<AppUser> signInWithAppleIdToken({required String idToken});

  Future<void> signOut();
}
