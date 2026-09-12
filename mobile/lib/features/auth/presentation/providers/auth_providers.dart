import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/env.dart';
import '../../../../core/network/supabase_client_provider.dart';
import '../../data/native_oauth_service.dart';
import '../../data/repositories/supabase_auth_repository.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/repositories/auth_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return SupabaseAuthRepository(ref.watch(supabaseClientProvider));
});

final nativeOAuthServiceProvider = Provider<NativeOAuthService>((ref) => NativeOAuthService());

/// Google sign-in (Faz 11, madde 5 — see docs/roadmap.md) is hidden
/// entirely (see `LoginScreen`) rather than shown broken when
/// `mobile/.env` has neither `GOOGLE_CLIENT_ID` nor
/// `GOOGLE_SERVER_CLIENT_ID` set — same "missing config means the
/// feature is off, not an error" contract `apiClientProvider` already
/// uses for the AI backend. Also hidden on any platform where
/// `google_sign_in` itself can't do the imperative flow this app uses
/// at all — web, today (Faz 12, madde 11, denetim düzeltmesi, see
/// docs/roadmap.md: configuring the env vars alone used to be enough
/// to show a button that would always throw the moment it was tapped
/// on web) — see `NativeOAuthService.isGoogleAvailable`'s docstring.
final googleSignInAvailableProvider = Provider<bool>((ref) {
  final configured = Env.googleClientId != null || Env.googleServerClientId != null;
  return configured && ref.watch(nativeOAuthServiceProvider).isGoogleAvailable;
});

/// Apple sign-in only on iOS/macOS — see `NativeOAuthService.
/// isAppleAvailable`'s docstring for why Android isn't included.
final appleSignInAvailableProvider = Provider<bool>((ref) {
  return ref.watch(nativeOAuthServiceProvider).isAppleAvailable;
});

/// Raw session stream — this is what `app_router.dart` listens to for
/// redirect decisions (logged in vs logged out).
final authStateChangesProvider = StreamProvider<AppUser?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges();
});

/// The signed-in user's id, or `null` — derived from
/// [authStateChangesProvider] rather than each per-user provider reading
/// Supabase's `currentUser` directly at its own construction time.
///
/// **Faz 12 — denetim düzeltmesi (see docs/roadmap.md)**: `itemsProvider`/
/// `itemRepositoryProvider` and friends used to read the signed-in
/// user's id exactly once, when first built, then bind a Drift stream to
/// that id forever — switching accounts within the same app session
/// (sign out A, sign in B, no full app restart) left Home/Library
/// showing **A's** items until something else happened to dispose and
/// rebuild those providers, which nothing reliably did. Every provider
/// that needs "the current user" should `ref.watch` this one instead
/// (directly, or transitively through `itemRepositoryProvider`/
/// `collectionRepositoryProvider`) so Riverpod actually rebuilds them —
/// and their underlying Drift streams — the moment the session changes.
///
/// Defensive like `SyncService._currentUserIdOrNull()`/`search_providers
/// .dart`'s `_currentUserIdOrNull()`: `Supabase.instance` asserts if
/// `Supabase.initialize()` never ran, which a widget test that overrides
/// a downstream provider (bypassing this one entirely) shouldn't need to
/// know or care about.
final currentUserIdProvider = Provider<String?>((ref) {
  try {
    return ref.watch(authStateChangesProvider).valueOrNull?.id;
  } catch (_) {
    return null;
  }
});

final authControllerProvider = AsyncNotifierProvider<AuthController, AppUser?>(
  AuthController.new,
);

/// Owns the sign-in/sign-up/sign-out actions and their loading/error state.
/// Screens read `authControllerProvider` for that state and call these
/// methods — they never talk to `AuthRepository` directly.
class AuthController extends AsyncNotifier<AppUser?> {
  @override
  AppUser? build() {
    // Keep this notifier's state in sync with the session stream so a
    // token refresh or an external sign-out (e.g. expired session) is
    // reflected here too, not just in authStateChangesProvider.
    ref.listen(authStateChangesProvider, (previous, next) {
      next.whenData((user) => state = AsyncData(user));
    });
    return ref.read(authRepositoryProvider).currentUser;
  }

  Future<void> signIn({required String email, required String password}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(authRepositoryProvider).signIn(email: email, password: password),
    );
  }

  Future<void> signUp({required String email, required String password}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(authRepositoryProvider).signUp(email: email, password: password),
    );
  }

  /// Fetches a Google ID token via the native picker (`NativeOAuthService`)
  /// and exchanges it for a Supabase session. A cancelled picker leaves
  /// `state` as `AsyncData(null)` (still signed out) rather than an
  /// error — there's nothing wrong to report, the user just backed out.
  Future<void> signInWithGoogle() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final idToken = await ref.read(nativeOAuthServiceProvider).signInWithGoogle();
      if (idToken == null) return null;
      return ref.read(authRepositoryProvider).signInWithGoogleIdToken(idToken: idToken);
    });
  }

  /// Same contract as [signInWithGoogle], for Apple.
  Future<void> signInWithApple() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final idToken = await ref.read(nativeOAuthServiceProvider).signInWithApple();
      if (idToken == null) return null;
      return ref.read(authRepositoryProvider).signInWithAppleIdToken(idToken: idToken);
    });
  }

  Future<void> signOut() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(authRepositoryProvider).signOut();
      return null;
    });
  }
}
