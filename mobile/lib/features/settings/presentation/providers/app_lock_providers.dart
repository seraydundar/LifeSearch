import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/app_lock_service.dart';

final appLockServiceProvider = Provider<AppLockService>((ref) => AppLockService());

/// Whether the user has turned app-lock on, persisted in secure storage.
/// Settings' toggle updates this through [setEnabled].
final appLockEnabledProvider =
    AsyncNotifierProvider<AppLockEnabledController, bool>(AppLockEnabledController.new);

class AppLockEnabledController extends AsyncNotifier<bool> {
  @override
  Future<bool> build() => ref.read(appLockServiceProvider).isEnabled();

  Future<void> setEnabled(bool enabled) async {
    await ref.read(appLockServiceProvider).setEnabled(enabled);
    state = AsyncValue.data(enabled);
  }
}

/// Whether this device can even do biometric/PIN auth — Settings hides the
/// toggle when false.
final appLockDeviceSupportedProvider = FutureProvider<bool>((ref) {
  return ref.read(appLockServiceProvider).isDeviceSupported();
});

/// In-memory only, never persisted — a cold start always begins locked
/// (false) whenever app-lock is enabled. [AppLockGate] flips this back to
/// false whenever the app returns from the background, so re-authenticating
/// is required again rather than staying unlocked forever once the app has
/// been opened once.
final appLockUnlockedProvider = StateProvider<bool>((ref) => false);
