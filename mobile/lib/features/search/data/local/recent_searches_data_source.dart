import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';

/// Local-only search history (requirements doc, section 30) — never
/// leaves the device.
class RecentSearchesDataSource {
  RecentSearchesDataSource(this._db);

  final AppDatabase _db;
  static const _maxEntries = 10;

  Stream<List<String>> watchRecent() {
    final query = _db.select(_db.recentSearches)
      ..orderBy([(t) => OrderingTerm.desc(t.searchedAt)])
      ..limit(_maxEntries);
    return query.watch().map((rows) => rows.map((r) => r.query).toSet().toList());
  }

  Future<void> record(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    // Keep it a set of recent *distinct* queries: drop any earlier
    // occurrence of the same text before inserting the new one.
    await (_db.delete(_db.recentSearches)..where((t) => t.query.equals(trimmed))).go();
    await _db.into(_db.recentSearches).insert(RecentSearchesCompanion.insert(query: trimmed));
  }

  Future<void> clear() {
    return _db.delete(_db.recentSearches).go();
  }
}
