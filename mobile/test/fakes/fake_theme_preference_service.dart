import 'package:flutter/material.dart';
import 'package:lifesearch/features/settings/data/theme_preference_service.dart';

class FakeThemePreferenceService implements ThemePreferenceService {
  // No "System" mode exists in the real service anymore (only Light/Dark)
  // — defaulting to it here would make `SegmentedButton`'s `selected`
  // a value absent from its own segments.
  FakeThemePreferenceService({ThemeMode initial = ThemeMode.light}) : _mode = initial;

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
