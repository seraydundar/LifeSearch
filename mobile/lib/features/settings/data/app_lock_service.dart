import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// Wraps device biometrics/PIN authentication (`local_auth`) and persists
/// whether app-lock is turned on (`flutter_secure_storage` — the first
/// real use of a dependency that had sat unused in pubspec.yaml since
/// Phase 1).
///
/// The persisted value is just a boolean flag, not itself sensitive; using
/// secure storage for it is a convenient way to finally exercise the
/// dependency rather than a security requirement of this particular value.
class AppLockService {
  AppLockService({LocalAuthentication? localAuth, FlutterSecureStorage? secureStorage})
      : _localAuth = localAuth ?? LocalAuthentication(),
        _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const _enabledKey = 'app_lock_enabled';

  final LocalAuthentication _localAuth;
  final FlutterSecureStorage _secureStorage;

  Future<bool> isEnabled() async {
    final value = await _secureStorage.read(key: _enabledKey);
    return value == 'true';
  }

  Future<void> setEnabled(bool enabled) async {
    await _secureStorage.write(key: _enabledKey, value: enabled.toString());
  }

  /// Whether this device can even do biometric/PIN auth (biometrics
  /// enrolled, or a device passcode/PIN set) — Settings hides the toggle
  /// when this is false rather than offering a switch that could never be
  /// unlocked again.
  Future<bool> isDeviceSupported() async {
    try {
      return await _localAuth.isDeviceSupported();
    } on Exception {
      return false;
    }
  }

  /// `biometricOnly: false` lets the OS fall back to the device's own
  /// PIN/passcode when biometrics aren't enrolled or fail — matching the
  /// feature as scoped ("biometric/PIN kilidi"), not just fingerprint/Face
  /// ID. `persistAcrossBackgrounding: true` keeps the challenge alive if the
  /// OS briefly backgrounds the app to show the biometric UI itself.
  Future<bool> authenticate() async {
    try {
      return await _localAuth.authenticate(
        localizedReason: 'Uygulamanın kilidini açmak için kimliğini doğrula',
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
    } on Exception {
      return false;
    }
  }
}
