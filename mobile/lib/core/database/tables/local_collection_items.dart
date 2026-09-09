import 'package:drift/drift.dart';

/// Local cache of the `collection_items` junction table (see
/// infra/supabase/migrations/0008_collections.sql). sqlite doesn't
/// enforce the foreign-key cascade automatically here — deleting a
/// collection also explicitly deletes its rows in this table (see
/// `CollectionLocalDataSource.delete`).
class LocalCollectionItems extends Table {
  TextColumn get collectionId => text()();
  TextColumn get itemId => text()();
  DateTimeColumn get addedAt => dateTime()();

  /// 'synced' | 'pending' — a pending row has a matching SyncQueueEntries
  /// row driving the retry. No 'failed' state: unlike an item/collection,
  /// a failed add/remove doesn't leave anything else in a bad state, so
  /// the UI doesn't need to distinguish it — the queue's retry (and
  /// Settings' pending count) already surfaces the failure.
  TextColumn get syncStatus => text().withDefault(const Constant('synced'))();

  @override
  Set<Column> get primaryKey => {collectionId, itemId};
}
