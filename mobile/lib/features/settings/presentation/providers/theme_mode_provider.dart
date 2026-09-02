import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// In-memory for now (defaults to following the system theme). Persisting
/// the choice is a Phase 3 concern once Drift's local key-value storage
/// exists.
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);
