import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesearch/core/database/app_database.dart';
import 'package:lifesearch/features/collections/data/local/collection_local_data_source.dart';

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
}
