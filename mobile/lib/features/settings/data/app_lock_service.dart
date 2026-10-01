import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// Wraps device biometrics/PIN auth and persists the app-lock toggle; the toggle itself isn't sensitive data.
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

  /// Settings hides the toggle when this is false rather than offering a switch that could never unlock.
  Future<bool> isDeviceSupported() async {
    try {
      return await _localAuth.isDeviceSupported();
    } on Exception {
      return false;
    }
  }

  /// `biometricOnly: false` allows PIN/passcode fallback; `persistAcrossBackgrounding` survives the OS's own biometric UI backgrounding the app.
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
