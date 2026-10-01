import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_database.dart';

/// One `AppDatabase` (and one open sqlite connection) for the app's lifetime.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
