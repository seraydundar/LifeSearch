import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesearch/core/database/app_database.dart';
import 'package:lifesearch/features/item/data/local/item_local_data_source.dart';
import 'package:lifesearch/features/item/data/local/sync_queue_data_source.dart';
import 'package:lifesearch/features/item/domain/entities/item.dart';

void main() {
  late AppDatabase db;
  late ItemLocalDataSource dataSource;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dataSource = ItemLocalDataSource(db);
  });

  tearDown(() => db.close());

  Future<void> insertItem({required String id, required String userId}) {
    return db.into(db.localItems).insert(LocalItemsCompanion.insert(
          id: id,
          userId: userId,
          type: ItemType.note.dbValue,
          title: Value('$userId\'s note'),
          noteContent: const Value('secret body'),
          createdAt: DateTime(2026, 1, 1),
        ));
  }

  group('findById (Faz 12, madde 3 — see docs/roadmap.md)', () {
    test('returns the item when it belongs to the given user', () async {
      await insertItem(id: 'item-1', userId: 'user-a');

      final result = await dataSource.findById('user-a', 'item-1');

      expect(result?.id, 'item-1');
      expect(result?.noteContent, 'secret body');
    });

    test(
        "does not return another account's cached item, even though it's still on "
        'this device (a real, previously-unfixed scenario — an item stays cached '
        'locally after sign-out, see Faz 10a\'s own documented limitation)', () async {
      await insertItem(id: 'a-item', userId: 'user-a');

      final asB = await dataSource.findById('user-b', 'a-item');

      expect(asB, isNull);
    });

    test('a nonexistent id returns null regardless of user', () async {
      final result = await dataSource.findById('user-a', 'does-not-exist');

      expect(result, isNull);
    });
  });

  group('transaction (P1-03, docs/requirements-audit-2026-09-13.md)', () {
    test('commits every write made inside it', () async {
      final queue = SyncQueueDataSource(db);

      await dataSource.transaction(() async {
        await dataSource.upsert(LocalItemsCompanion.insert(
          id: 'item-1',
          userId: 'user-a',
          type: ItemType.note.dbValue,
          createdAt: DateTime(2026, 1, 1),
        ));
        await queue.enqueue(
          userId: 'user-a',
          operationType: 'create_note',
          itemId: 'item-1',
          payload: const {'title': 'x'},
        );
      });

      expect(await dataSource.findById('user-a', 'item-1'), isNotNull);
      expect(await queue.pendingEntries('user-a'), hasLength(1));
    });

    test(
        'a failure partway through rolls back every write made so far — no '
        'local-only mutation left with no queue entry to ever push it', () async {
      final queue = _ThrowingSyncQueueDataSource(db);

      await expectLater(
        dataSource.transaction(() async {
          await dataSource.upsert(LocalItemsCompanion.insert(
            id: 'item-1',
            userId: 'user-a',
            type: ItemType.note.dbValue,
            createdAt: DateTime(2026, 1, 1),
          ));
          // Stands in for the app dying, a disk error, or any other
          // failure between the local write and the enqueue call that
          // used to be two separate, unguarded `await`s.
          await queue.enqueue(
            userId: 'user-a',
            operationType: 'create_note',
            itemId: 'item-1',
            payload: const {'title': 'x'},
          );
        }),
        throwsA(isA<Exception>()),
      );

      // Rolled back, not left as an orphaned local write that
      // `SyncService._pullRemote` would later delete outright, having
      // no server row and no pending queue entry to explain it away.
      expect(await dataSource.findById('user-a', 'item-1'), isNull);
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
