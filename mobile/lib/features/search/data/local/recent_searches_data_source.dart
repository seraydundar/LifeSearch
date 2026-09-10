import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';

/// Local-only search history (requirements doc, section 30) — never
/// leaves the device. Scoped by `userId` so a shared device's accounts
/// don't see (or clear) each other's search history — see
/// `RecentSearches.userId`'s docstring.
class RecentSearchesDataSource {
  RecentSearchesDataSource(this._db);

  final AppDatabase _db;
  static const _maxEntries = 10;

  Stream<List<String>> watchRecent(String userId) {
    // `id DESC` as a tiebreaker, not just `searchedAt DESC`: the column's
    // `currentDateAndTime` default is only second-precision, so a
    // re-search that lands in the same wall-clock second as the previous
    // entry (routine in a test, plausible for a fast re-search in real
    // use too) would otherwise tie and fall back to an unspecified scan
    // order — `id` is a monotonically increasing autoincrement, so it
    // always breaks the tie the right way (most recently inserted first).
    final query = _db.select(_db.recentSearches)
      ..where((t) => t.userId.equals(userId))
      ..orderBy([(t) => OrderingTerm.desc(t.searchedAt), (t) => OrderingTerm.desc(t.id)])
      ..limit(_maxEntries);
    return query.watch().map((rows) => rows.map((r) => r.query).toSet().toList());
  }

  Future<void> record(String userId, String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    // Keep it a set of recent *distinct* queries: drop any earlier
    // occurrence of the same text before inserting the new one.
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
