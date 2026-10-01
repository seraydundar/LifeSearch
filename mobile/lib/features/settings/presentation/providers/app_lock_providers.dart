import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/app_lock_service.dart';

final appLockServiceProvider = Provider<AppLockService>((ref) => AppLockService());

/// Whether app-lock is on, persisted in secure storage; Settings updates it through [setEnabled].
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

/// Whether this device can even do biometric/PIN auth — Settings hides the toggle when false.
final appLockDeviceSupportedProvider = FutureProvider<bool>((ref) {
  return ref.read(appLockServiceProvider).isDeviceSupported();
});

/// In-memory only; starts locked on cold start, and [AppLockGate] re-locks it on every background return.
final appLockUnlockedProvider = StateProvider<bool>((ref) => false);
