import 'package:drift/drift.dart';

/// Local-only search history (requirements doc, section 30). No screen
/// writes to this yet — the search UI itself lands in Phase 5 — but the
/// table exists now so that feature doesn't need its own migration later.
class RecentSearches extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get query => text()();
  DateTimeColumn get searchedAt => dateTime().withDefault(currentDateAndTime)();
}
