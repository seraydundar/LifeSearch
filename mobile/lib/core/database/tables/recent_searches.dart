import 'package:drift/drift.dart';

/// Local-only search history.
class RecentSearches extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Default '' exists only for the v6->v7 migration's backfill; every real insert supplies it.
  TextColumn get userId => text().withDefault(const Constant(''))();
  TextColumn get query => text()();
  DateTimeColumn get searchedAt => dateTime().withDefault(currentDateAndTime)();
}
