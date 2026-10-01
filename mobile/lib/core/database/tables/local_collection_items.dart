import 'package:drift/drift.dart';

/// Local cache of the `collection_items` junction table. sqlite doesn't cascade deletes
/// here — deleting a collection must also explicitly delete its rows (see `CollectionLocalDataSource.delete`).
class LocalCollectionItems extends Table {
  TextColumn get collectionId => text()();
  TextColumn get itemId => text()();
  DateTimeColumn get addedAt => dateTime()();

  /// 'synced' | 'pending' (no 'failed' — a failed add/remove leaves nothing else inconsistent).
  TextColumn get syncStatus => text().withDefault(const Constant('synced'))();

  @override
  Set<Column> get primaryKey => {collectionId, itemId};
}
