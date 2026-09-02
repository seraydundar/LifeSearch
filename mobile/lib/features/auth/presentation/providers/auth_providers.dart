import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/supabase_client_provider.dart';
import '../../data/repositories/supabase_auth_repository.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/repositories/auth_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return SupabaseAuthRepository(ref.watch(supabaseClientProvider));
});

/// Raw session stream — this is what `app_router.dart` listens to for
/// redirect decisions (logged in vs logged out).
final authStateChangesProvider = StreamProvider<AppUser?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges();
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

  Future<void> signOut() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(authRepositoryProvider).signOut();
      return null;
    });
  }
}
