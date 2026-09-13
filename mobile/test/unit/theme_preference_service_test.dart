import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesearch/features/settings/data/theme_preference_service.dart';
import 'package:mocktail/mocktail.dart';

class _MockSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  late _MockSecureStorage secureStorage;
  late ThemePreferenceService service;

  setUp(() {
    secureStorage = _MockSecureStorage();
    service = ThemePreferenceService(secureStorage: secureStorage);
  });

  group('load', () {
    test('is ThemeMode.system when nothing has been persisted yet', () async {
      when(() => secureStorage.read(key: 'theme_mode')).thenAnswer((_) async => null);

      expect(await service.load(), ThemeMode.system);
    });

    test('resolves a persisted "light" value', () async {
      when(() => secureStorage.read(key: 'theme_mode')).thenAnswer((_) async => 'light');

      expect(await service.load(), ThemeMode.light);
    });

    test('resolves a persisted "dark" value', () async {
      when(() => secureStorage.read(key: 'theme_mode')).thenAnswer((_) async => 'dark');

      expect(await service.load(), ThemeMode.dark);
    });

    test('falls back to ThemeMode.system for an unrecognized persisted value', () async {
      // Defensive against a future app version removing a ThemeMode value
      // (unlikely, but cheaper to handle than to assume away).
      when(() => secureStorage.read(key: 'theme_mode')).thenAnswer((_) async => 'garbled');

      expect(await service.load(), ThemeMode.system);
    });
  });

  test('save persists the mode by its enum name', () async {
    when(() => secureStorage.write(key: any(named: 'key'), value: any(named: 'value')))
        .thenAnswer((_) async {});

    await service.save(ThemeMode.dark);

    verify(() => secureStorage.write(key: 'theme_mode', value: 'dark')).called(1);
  });
}
