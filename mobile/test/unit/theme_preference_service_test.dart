import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesearch/features/settings/data/theme_preference_service.dart';
import 'package:mocktail/mocktail.dart';

class _MockSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late _MockSecureStorage secureStorage;
  late ThemePreferenceService service;

  setUp(() {
    secureStorage = _MockSecureStorage();
    service = ThemePreferenceService(secureStorage: secureStorage);
    when(() => secureStorage.write(key: any(named: 'key'), value: any(named: 'value')))
        .thenAnswer((_) async {});
  });

  tearDown(() => binding.platformDispatcher.clearPlatformBrightnessTestValue());

  group('load', () {
    // There's no "System" mode to fall back to — only Light/Dark. The
    // very first time nothing has been persisted, the user asked for
    // "whichever mode the phone is in at first launch", locked in from
    // then on (not a continuously-following system theme).
    test('locks in the phone\'s current theme when nothing has been persisted yet', () async {
      when(() => secureStorage.read(key: 'theme_mode')).thenAnswer((_) async => null);
      binding.platformDispatcher.platformBrightnessTestValue = Brightness.dark;

      expect(await service.load(), ThemeMode.dark);
      verify(() => secureStorage.write(key: 'theme_mode', value: 'dark')).called(1);
    });

    test('a light phone theme is locked in the same way', () async {
      when(() => secureStorage.read(key: 'theme_mode')).thenAnswer((_) async => null);
      binding.platformDispatcher.platformBrightnessTestValue = Brightness.light;

      expect(await service.load(), ThemeMode.light);
      verify(() => secureStorage.write(key: 'theme_mode', value: 'light')).called(1);
    });

    test('resolves a persisted "light" value without touching the phone theme', () async {
      when(() => secureStorage.read(key: 'theme_mode')).thenAnswer((_) async => 'light');
      binding.platformDispatcher.platformBrightnessTestValue = Brightness.dark;

      expect(await service.load(), ThemeMode.light);
      verifyNever(() => secureStorage.write(key: any(named: 'key'), value: any(named: 'value')));
    });

    test('resolves a persisted "dark" value without touching the phone theme', () async {
      when(() => secureStorage.read(key: 'theme_mode')).thenAnswer((_) async => 'dark');
      binding.platformDispatcher.platformBrightnessTestValue = Brightness.light;

      expect(await service.load(), ThemeMode.dark);
      verifyNever(() => secureStorage.write(key: any(named: 'key'), value: any(named: 'value')));
    });

    test('an unrecognized persisted value is treated the same as nothing saved', () async {
      // Defensive against a future app version removing a ThemeMode
      // value (unlikely, but cheaper to handle than to assume away).
      when(() => secureStorage.read(key: 'theme_mode')).thenAnswer((_) async => 'garbled');
      binding.platformDispatcher.platformBrightnessTestValue = Brightness.dark;

      expect(await service.load(), ThemeMode.dark);
    });
  });

  test('save persists the mode by its enum name', () async {
    await service.save(ThemeMode.dark);

    verify(() => secureStorage.write(key: 'theme_mode', value: 'dark')).called(1);
  });
}
