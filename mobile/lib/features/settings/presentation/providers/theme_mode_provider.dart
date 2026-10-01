import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/theme_preference_service.dart';

final themePreferenceServiceProvider = Provider<ThemePreferenceService>((ref) {
  return ThemePreferenceService();
});

/// AsyncLoading is treated as ThemeMode.system (a transient fallback) until secure storage resolves to the saved or newly locked-in theme.
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
