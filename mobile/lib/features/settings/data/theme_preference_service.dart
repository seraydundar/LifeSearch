import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the user's Light/Dark choice (requirements doc, section
/// 50) — P3 (docs/requirements-audit-2026-09-13.md): the choice used to
/// live only in a `StateProvider`, so a cold restart always fell back to
/// following the system theme regardless of what was last picked.
/// `flutter_secure_storage`, same as `AppLockService` — not itself
/// sensitive data, but already a dependency, and Drift has no generic
/// key-value settings table yet to use instead (see that class's own
/// docstring for the same tradeoff).
///
/// There's no "follow the system" mode here — the toggle is only
/// Light/Dark. The first time there's nothing saved yet, [load] reads
/// the phone's *current* theme once and locks it in as an explicit
/// choice (persisted immediately), rather than returning `ThemeMode
/// .system`, which would keep silently following every later OS theme
/// change. The user explicitly asked for "whichever mode the phone is
/// in at first launch, then stays whatever it's set to until changed
/// here" — a one-time read, not a continuous following.
class ThemePreferenceService {
  ThemePreferenceService({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const _key = 'theme_mode';

  final FlutterSecureStorage _secureStorage;

  Future<ThemeMode> load() async {
    final value = await _secureStorage.read(key: _key);
    if (value == 'light') return ThemeMode.light;
    if (value == 'dark') return ThemeMode.dark;

    // `WidgetsBinding.instance.platformDispatcher`, not the raw `dart:ui`
    // `PlatformDispatcher.instance` singleton — the latter can't be
    // overridden by `TestWidgetsFlutterBinding` in tests, which would
    // make this depend on whatever brightness the test-running machine
    // happens to be in.
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
