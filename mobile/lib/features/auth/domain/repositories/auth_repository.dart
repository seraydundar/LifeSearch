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

  Future<void> signOut();
}
