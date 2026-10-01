import '../entities/app_user.dart';

/// Contract the presentation layer codes against; tests can supply a fake.
abstract interface class AuthRepository {
  /// Emits on sign-in/sign-out/session-refresh; the router watches this for redirect decisions.
  Stream<AppUser?> authStateChanges();

  AppUser? get currentUser;

  Future<AppUser> signIn({required String email, required String password});

  Future<AppUser> signUp({required String email, required String password});

  /// Exchanges a Google ID token (from `NativeOAuthService`); creates the account on first use, like `signUp`.
  Future<AppUser> signInWithGoogleIdToken({required String idToken});

  /// Same contract as [signInWithGoogleIdToken], for Apple's identity token.
  Future<AppUser> signInWithAppleIdToken({required String idToken});

  Future<void> signOut();
}
