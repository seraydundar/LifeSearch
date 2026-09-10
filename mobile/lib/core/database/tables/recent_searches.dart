import 'package:drift/drift.dart';

/// Local-only search history (requirements doc, section 30). No screen
/// writes to this yet — the search UI itself lands in Phase 5 — but the
/// table exists now so that feature doesn't need its own migration later.
class RecentSearches extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Whose search history this entry belongs to — without it, every
  /// account on a shared device sees (and clears) the same list. Default
  /// exists only for the v6->v7 migration's `ALTER TABLE ADD COLUMN`;
  /// every real insert always supplies it.
  TextColumn get userId => text().withDefault(const Constant(''))();
  TextColumn get query => text()();
  DateTimeColumn get searchedAt => dateTime().withDefault(currentDateAndTime)();
}
