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

/// Hidden (not shown broken) when unconfigured or the platform can't do the native flow (e.g. web).
final googleSignInAvailableProvider = Provider<bool>((ref) {
  final configured = Env.googleClientId != null || Env.googleServerClientId != null;
  return configured && ref.watch(nativeOAuthServiceProvider).isGoogleAvailable;
});

final appleSignInAvailableProvider = Provider<bool>((ref) {
  return ref.watch(nativeOAuthServiceProvider).isAppleAvailable;
});

/// What `app_router.dart` watches for redirect decisions (logged in vs out).
final authStateChangesProvider = StreamProvider<AppUser?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges();
});

/// Watch this, not `currentUser` directly, so per-user providers/Drift streams rebuild on account switch.
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
class AuthController extends AsyncNotifier<AppUser?> {
  @override
  AppUser? build() {
    // Mirror the session stream so an external refresh/sign-out updates state too.
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

  /// Cancelling the picker leaves state signed out, not an error.
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
