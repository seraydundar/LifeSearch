import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/theme_preference_service.dart';

final themePreferenceServiceProvider = Provider<ThemePreferenceService>((ref) {
  return ThemePreferenceService();
});

/// The user's Light/Dark/System choice, persisted (P3, docs/
/// requirements-audit-2026-09-13.md — this used to be in-memory only,
/// via a plain `StateProvider`, so a cold restart always reverted to
/// following the system theme). Same `AsyncNotifierProvider` shape as
/// `appLockEnabledProvider`: starts loading (`AsyncLoading`, which
/// `LifeSearchApp`/`SettingsScreen` treat the same as
/// `ThemeMode.system` via `.valueOrNull ?? ThemeMode.system`) and
/// resolves to whatever was last saved, or `ThemeMode.system` the very
/// first time there's nothing saved yet.
final themeModeProvider =
    AsyncNotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

class ThemeModeController extends AsyncNotifier<ThemeMode> {
  @override
  Future<ThemeMode> build() => ref.read(themePreferenceServiceProvider).load();

  Future<void> setThemeMode(ThemeMode mode) async {
    await ref.read(themePreferenceServiceProvider).save(mode);
    state = AsyncValue.data(mode);
  }
}
