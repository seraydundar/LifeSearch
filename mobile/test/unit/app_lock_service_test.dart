import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesearch/features/settings/data/app_lock_service.dart';
import 'package:local_auth/local_auth.dart';
import 'package:mocktail/mocktail.dart';

class _MockLocalAuth extends Mock implements LocalAuthentication {}

class _MockSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  late _MockLocalAuth localAuth;
  late _MockSecureStorage secureStorage;
  late AppLockService service;

  setUp(() {
    localAuth = _MockLocalAuth();
    secureStorage = _MockSecureStorage();
    service = AppLockService(localAuth: localAuth, secureStorage: secureStorage);
  });

  group('isEnabled', () {
    test('is false when nothing has been persisted yet', () async {
      when(() => secureStorage.read(key: 'app_lock_enabled')).thenAnswer((_) async => null);

      expect(await service.isEnabled(), isFalse);
    });

    test('is true only when the persisted value is exactly "true"', () async {
      when(() => secureStorage.read(key: 'app_lock_enabled')).thenAnswer((_) async => 'true');

      expect(await service.isEnabled(), isTrue);
    });
  });

  test('setEnabled persists the boolean as a string', () async {
    when(() => secureStorage.write(key: any(named: 'key'), value: any(named: 'value')))
        .thenAnswer((_) async {});

    await service.setEnabled(true);

    verify(() => secureStorage.write(key: 'app_lock_enabled', value: 'true')).called(1);
  });

  group('isDeviceSupported', () {
    test('returns what local_auth reports', () async {
      when(() => localAuth.isDeviceSupported()).thenAnswer((_) async => true);

      expect(await service.isDeviceSupported(), isTrue);
    });

    test('treats a plugin error as unsupported rather than throwing', () async {
      when(() => localAuth.isDeviceSupported()).thenThrow(Exception('platform error'));

      expect(await service.isDeviceSupported(), isFalse);
    });
  });

  group('authenticate', () {
    test('returns what local_auth reports', () async {
      when(() => localAuth.authenticate(
            localizedReason: any(named: 'localizedReason'),
            biometricOnly: any(named: 'biometricOnly'),
            persistAcrossBackgrounding: any(named: 'persistAcrossBackgrounding'),
          )).thenAnswer((_) async => true);

      expect(await service.authenticate(), isTrue);
    });

    test('treats a plugin error as a failed authentication rather than throwing', () async {
      when(() => localAuth.authenticate(
            localizedReason: any(named: 'localizedReason'),
            biometricOnly: any(named: 'biometricOnly'),
            persistAcrossBackgrounding: any(named: 'persistAcrossBackgrounding'),
          )).thenThrow(Exception('platform error'));

      expect(await service.authenticate(), isFalse);
    });

    test('allows non-biometric fallback (device PIN/passcode)', () async {
      when(() => localAuth.authenticate(
            localizedReason: any(named: 'localizedReason'),
            biometricOnly: any(named: 'biometricOnly'),
            persistAcrossBackgrounding: any(named: 'persistAcrossBackgrounding'),
          )).thenAnswer((_) async => true);

      await service.authenticate();

      verify(() => localAuth.authenticate(
            localizedReason: any(named: 'localizedReason'),
            biometricOnly: false,
            persistAcrossBackgrounding: any(named: 'persistAcrossBackgrounding'),
          )).called(1);
    });
  });
}
