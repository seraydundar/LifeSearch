import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the user's Light/Dark/System choice (requirements doc,
/// section 50) — P3 (docs/requirements-audit-2026-09-13.md): the choice
/// used to live only in a `StateProvider`, so a cold restart always fell
/// back to following the system theme regardless of what was last
/// picked. `flutter_secure_storage`, same as `AppLockService` — not
/// itself sensitive data, but already a dependency, and Drift has no
/// generic key-value settings table yet to use instead (see that
/// class's own docstring for the same tradeoff).
class ThemePreferenceService {
  ThemePreferenceService({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const _key = 'theme_mode';

  final FlutterSecureStorage _secureStorage;

  Future<ThemeMode> load() async {
    final value = await _secureStorage.read(key: _key);
    return switch (value) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> save(ThemeMode mode) async {
    await _secureStorage.write(key: _key, value: mode.name);
  }
}
