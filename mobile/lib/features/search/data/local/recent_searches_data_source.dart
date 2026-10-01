import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';

class RecentSearchesDataSource {
  RecentSearchesDataSource(this._db);

  final AppDatabase _db;
  static const _maxEntries = 10;

  Stream<List<String>> watchRecent(String userId) {
    // `id DESC` tiebreaker: `searchedAt` is only second-precision, so same-second
    // re-searches would otherwise tie and sort unpredictably.
    final query = _db.select(_db.recentSearches)
      ..where((t) => t.userId.equals(userId))
      ..orderBy([(t) => OrderingTerm.desc(t.searchedAt), (t) => OrderingTerm.desc(t.id)])
      ..limit(_maxEntries);
    return query.watch().map((rows) => rows.map((r) => r.query).toSet().toList());
  }

  Future<void> record(String userId, String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    // Keep distinct: drop any earlier occurrence of the same text first.
    await (_db.delete(_db.recentSearches)
          ..where((t) => t.userId.equals(userId) & t.query.equals(trimmed)))
        .go();
    await _db.into(_db.recentSearches).insert(
          RecentSearchesCompanion.insert(userId: Value(userId), query: trimmed),
        );
  }

  Future<void> clear(String userId) {
    return (_db.delete(_db.recentSearches)..where((t) => t.userId.equals(userId))).go();
  }
}
