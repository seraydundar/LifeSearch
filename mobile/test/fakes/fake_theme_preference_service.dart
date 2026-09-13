import 'package:flutter/material.dart';
import 'package:lifesearch/features/settings/data/theme_preference_service.dart';

class FakeThemePreferenceService implements ThemePreferenceService {
  FakeThemePreferenceService({ThemeMode initial = ThemeMode.system}) : _mode = initial;

  ThemeMode _mode;
  int saveCallCount = 0;

  @override
  Future<ThemeMode> load() async => _mode;

  @override
  Future<void> save(ThemeMode mode) async {
    saveCallCount++;
    _mode = mode;
  }
}
