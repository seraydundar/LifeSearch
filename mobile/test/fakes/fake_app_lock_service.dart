import 'package:lifesearch/features/settings/data/app_lock_service.dart';

class FakeAppLockService implements AppLockService {
  FakeAppLockService({
    bool initiallyEnabled = false,
    this.deviceSupported = true,
    this.authenticateResult = true,
  }) : _enabled = initiallyEnabled;

  bool _enabled;
  bool deviceSupported;
  bool authenticateResult;
  int authenticateCallCount = 0;

  @override
  Future<bool> isEnabled() async => _enabled;

  @override
  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
  }

  @override
  Future<bool> isDeviceSupported() async => deviceSupported;

  @override
  Future<bool> authenticate() async {
    authenticateCallCount++;
    return authenticateResult;
  }
}
