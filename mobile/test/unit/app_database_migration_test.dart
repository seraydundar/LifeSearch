import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesearch/core/database/app_database.dart';

/// Tests the v6->v7 backfill (`AppDatabase.backfillSyncQueueOwnership`) in
/// isolation from the `ALTER TABLE ADD COLUMN` step around it — a fresh
/// `forTesting` database is already on the current (v7) schema, so rows are
/// inserted directly at the post-migration shape with `userId: ''` (the new
/// column's default, exactly what a real ALTER TABLE would have left
/// pre-existing rows at) rather than needing to fabricate an actual
/// old-schema sqlite file by hand.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> insertUnbackfilledEntry({
    required int id,
    required String operationType,
    required String itemId,
  }) {
    return db.into(db.syncQueueEntries).insert(
          SyncQueueEntriesCompanion.insert(
            id: Value(id),
            userId: const Value(''), // the ALTER TABLE default, pre-backfill
            operationType: operationType,
            itemId: itemId,
            payload: '{}',
          ),
        );
  }

  test('recovers an item-scoped entry\'s owner from the item it targets', () async {
    await db.into(db.localItems).insert(LocalItemsCompanion.insert(
          id: 'item-1',
          userId: 'user-1',
          type: 'note',
          createdAt: DateTime(2026, 1, 1),
        ));
    await insertUnbackfilledEntry(id: 1, operationType: 'create_note', itemId: 'item-1');

    await db.backfillSyncQueueOwnership();

    final entry = await (db.select(db.syncQueueEntries)..where((t) => t.id.equals(1))).getSingle();
    expect(entry.userId, 'user-1');
  });

  test('recovers a collection-scoped entry\'s owner from the collection it targets', () async {
    await db.into(db.localCollections).insert(LocalCollectionsCompanion.insert(
          id: 'coll-1',
          userId: 'user-2',
          name: 'Docker stuff',
          createdAt: DateTime(2026, 1, 1),
        ));
    await insertUnbackfilledEntry(id: 1, operationType: 'add_to_collection', itemId: 'coll-1');

    await db.backfillSyncQueueOwnership();

    final entry = await (db.select(db.syncQueueEntries)..where((t) => t.id.equals(1))).getSingle();
    expect(entry.userId, 'user-2');
  });

  test('drops an entry whose target no longer exists locally, rather than guessing', () async {
    // No matching local_items/local_collections row for 'item-gone' — its
    // owner can't be recovered, so this must not survive with an empty
    // (or worse, wrong) userId.
    await insertUnbackfilledEntry(id: 1, operationType: 'create_note', itemId: 'item-gone');

    await db.backfillSyncQueueOwnership();

    final remaining = await db.select(db.syncQueueEntries).get();
    expect(remaining, isEmpty);
  });

  test('a mix of entries only keeps the ones it could actually attribute', () async {
    await db.into(db.localItems).insert(LocalItemsCompanion.insert(
          id: 'item-1',
          userId: 'user-1',
          type: 'note',
          createdAt: DateTime(2026, 1, 1),
        ));
    await insertUnbackfilledEntry(id: 1, operationType: 'create_note', itemId: 'item-1');
    await insertUnbackfilledEntry(id: 2, operationType: 'update_note', itemId: 'item-gone');

    await db.backfillSyncQueueOwnership();

    final remaining = await db.select(db.syncQueueEntries).get();
    expect(remaining.map((e) => e.id), [1]);
    expect(remaining.single.userId, 'user-1');
  });
}
