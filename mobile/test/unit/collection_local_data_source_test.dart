import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesearch/core/database/app_database.dart';
import 'package:lifesearch/features/collections/data/local/collection_local_data_source.dart';
import 'package:lifesearch/features/item/data/local/sync_queue_data_source.dart';

void main() {
  late AppDatabase db;
  late CollectionLocalDataSource dataSource;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dataSource = CollectionLocalDataSource(db);
  });

  tearDown(() => db.close());

  Future<void> insertCollection({required String id, required String userId}) {
    return dataSource.upsert(LocalCollectionsCompanion.insert(
      id: id,
      userId: userId,
      name: '$userId\'s collection',
      createdAt: DateTime(2026, 1, 1),
    ));
  }

  Future<void> insertItem({
    required String id,
    required String userId,
    bool private = false,
  }) {
    return db.into(db.localItems).insert(LocalItemsCompanion.insert(
          id: id,
          userId: userId,
          type: 'note',
          createdAt: DateTime(2026, 1, 1),
          private: Value(private),
        ));
  }

  group('allMemberships (Faz 12, madde 4 — see docs/roadmap.md)', () {
    test("returns only the given user's own memberships", () async {
      await insertCollection(id: 'coll-a', userId: 'user-a');
      await dataSource.addItem('coll-a', 'item-1', syncStatus: 'synced');

      final memberships = await dataSource.allMemberships('user-a');

      expect(memberships, [('coll-a', 'item-1')]);
    });

    test(
        "does not return a different account's still-cached membership — "
        '`LocalCollectionItems` carries no userId column of its own, so this has to '
        'come from joining LocalCollections (a real, previously-unfixed scenario: '
        "SyncService used to delete these as if they were user-b's own stale rows)",
        () async {
      await insertCollection(id: 'coll-a', userId: 'user-a');
      await dataSource.addItem('coll-a', 'item-1', syncStatus: 'synced');
      await insertCollection(id: 'coll-b', userId: 'user-b');
      await dataSource.addItem('coll-b', 'item-2', syncStatus: 'synced');

      final asA = await dataSource.allMemberships('user-a');
      final asB = await dataSource.allMemberships('user-b');

      expect(asA, [('coll-a', 'item-1')]);
      expect(asB, [('coll-b', 'item-2')]);
    });

    test('a membership whose collection is not cached at all for that user is excluded',
        () async {
      // Defensive: a membership row somehow outliving its own collection
      // row shouldn't show up for anyone, rather than crash the join.
      await dataSource.addItem('orphan-coll', 'item-1', syncStatus: 'synced');

      final memberships = await dataSource.allMemberships('user-a');

      expect(memberships, isEmpty);
    });
  });

  group('watchItemsForCollection (P1-01/P1-02, docs/requirements-audit-2026-09-13.md)', () {
    test('only resolves for the collection\'s own owner, not by collectionId alone', () async {
      // Same collectionId as another account's cached collection — a
      // stale id left over in route state after an account switch (or a
      // shared device's cache not yet purged) used to be enough to see
      // through it, since the old query never checked ownership at all.
      await insertCollection(id: 'shared-id', userId: 'user-a');
      await insertItem(id: 'a-item', userId: 'user-a');
      await dataSource.addItem('shared-id', 'a-item', syncStatus: 'synced');

      final asOwner = await dataSource.watchItemsForCollection('shared-id', 'user-a').first;
      final asOther = await dataSource.watchItemsForCollection('shared-id', 'user-b').first;

      expect(asOwner.map((i) => i.id), ['a-item']);
      expect(asOther, isEmpty);
    });

    test('excludes a private item by default', () async {
      await insertCollection(id: 'coll-a', userId: 'user-a');
      await insertItem(id: 'secret', userId: 'user-a', private: true);
      await insertItem(id: 'public', userId: 'user-a');
      await dataSource.addItem('coll-a', 'secret', syncStatus: 'synced');
      await dataSource.addItem('coll-a', 'public', syncStatus: 'synced');

      final items = await dataSource.watchItemsForCollection('coll-a', 'user-a').first;

      expect(items.map((i) => i.id), ['public']);
    });

    test('includes a private item once includePrivate is true', () async {
      await insertCollection(id: 'coll-a', userId: 'user-a');
      await insertItem(id: 'secret', userId: 'user-a', private: true);
      await dataSource.addItem('coll-a', 'secret', syncStatus: 'synced');

      final items = await dataSource
          .watchItemsForCollection('coll-a', 'user-a', includePrivate: true)
          .first;

      expect(items.map((i) => i.id), ['secret']);
    });
  });

  group('transaction (P1-03, docs/requirements-audit-2026-09-13.md)', () {
    test('a failure partway through rolls back every write made so far', () async {
      final queue = _ThrowingSyncQueueDataSource(db);

      await expectLater(
        dataSource.transaction(() async {
          await insertCollection(id: 'coll-1', userId: 'user-a');
          await queue.enqueue(
            userId: 'user-a',
            operationType: 'create_collection',
            itemId: 'coll-1',
            payload: const {'name': 'x'},
          );
        }),
        throwsA(isA<Exception>()),
      );

      expect(await dataSource.allIds('user-a'), isEmpty);
      expect(await queue.pendingEntries('user-a'), isEmpty);
    });
  });
}

/// Stands in for a crash/error between the local write and the enqueue
/// call — `enqueue()` never actually reaches the database.
class _ThrowingSyncQueueDataSource extends SyncQueueDataSource {
  _ThrowingSyncQueueDataSource(super.db);

  @override
  Future<void> enqueue({
    required String userId,
    required String operationType,
    required String itemId,
    required Map<String, dynamic> payload,
  }) {
    throw Exception('simulated failure enqueuing');
  }
}
