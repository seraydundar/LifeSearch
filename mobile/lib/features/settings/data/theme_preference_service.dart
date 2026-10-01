import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// No "follow system" mode — on first launch [load] reads the phone's current theme once and locks it in, rather than tracking later OS changes.
class ThemePreferenceService {
  ThemePreferenceService({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const _key = 'theme_mode';

  final FlutterSecureStorage _secureStorage;

  Future<ThemeMode> load() async {
    final value = await _secureStorage.read(key: _key);
    if (value == 'light') return ThemeMode.light;
    if (value == 'dark') return ThemeMode.dark;

    // WidgetsBinding's platformDispatcher, not the dart:ui singleton, so tests can override brightness.
    final systemMode =
        WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark
            ? ThemeMode.dark
            : ThemeMode.light;
    await save(systemMode);
    return systemMode;
  }

  Future<void> save(ThemeMode mode) async {
    await _secureStorage.write(key: _key, value: mode.name);
  }
}
