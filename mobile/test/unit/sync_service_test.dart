import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesearch/core/database/app_database.dart';
import 'package:lifesearch/core/error/failure.dart';
import 'package:lifesearch/core/sync/sync_service.dart';
import 'package:lifesearch/features/collections/data/local/collection_local_data_source.dart';
import 'package:lifesearch/features/collections/data/remote/remote_collection_data_source.dart';
import 'package:lifesearch/features/item/data/local/item_local_data_source.dart';
import 'package:lifesearch/features/item/data/local/sync_queue_data_source.dart';
import 'package:lifesearch/features/item/data/remote/ai_processing_trigger.dart';
import 'package:lifesearch/features/item/data/remote/remote_item_data_source.dart';
import 'package:lifesearch/features/item/domain/entities/item.dart';
import 'package:mocktail/mocktail.dart';

class _MockRemote extends Mock implements RemoteItemDataSource {}

class _MockRemoteCollections extends Mock implements RemoteCollectionDataSource {}

void main() {
  late AppDatabase db;
  late ItemLocalDataSource local;
  late CollectionLocalDataSource localCollections;
  late SyncQueueDataSource queue;
  late _MockRemote remote;
  late _MockRemoteCollections remoteCollections;
  late SyncService sync;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    local = ItemLocalDataSource(db);
    localCollections = CollectionLocalDataSource(db);
    queue = SyncQueueDataSource(db);
    remote = _MockRemote();
    remoteCollections = _MockRemoteCollections();
    when(() => remote.userId).thenReturn('user-1');
    when(() => remote.fetchAllRows()).thenAnswer((_) async => []);
    when(() => remoteCollections.fetchAllRows()).thenAnswer((_) async => []);
    when(() => remoteCollections.fetchAllItemRows(any())).thenAnswer((_) async => []);
    // BACKEND_URL unset -> null Dio -> triggerProcessing() is a no-op.
    sync = SyncService(
      local: local,
      remote: remote,
      localCollections: localCollections,
      remoteCollections: remoteCollections,
      queue: queue,
      aiTrigger: AiProcessingTrigger(null),
    );
  });

  tearDown(() => db.close());

  test('does nothing when nobody is signed in', () async {
    when(() => remote.userId).thenThrow(const AuthFailure('no session'));

    await sync.syncNow();

    verifyNever(() => remote.fetchAllRows());
    verifyNever(() => remoteCollections.fetchAllRows());
  });

  test('pushes a queued create_note and marks it synced', () async {
    await local.upsert(LocalItemsCompanion.insert(
      id: 'note-1',
      userId: 'user-1',
      type: ItemType.note.dbValue,
      title: const Value('Docker Notes'),
      processingStatus: const Value('completed'),
      createdAt: DateTime(2026, 1, 1),
      noteContent: const Value('body'),
      syncStatus: const Value('pending'),
    ));
    await queue.enqueue(
      operationType: 'create_note',
      itemId: 'note-1',
      payload: {'title': 'Docker Notes', 'content': 'body'},
    );
    when(() => remote.createNote(
          id: 'note-1',
          title: 'Docker Notes',
          content: 'body',
        )).thenAnswer((_) async {});

    await sync.syncNow();

    verify(() => remote.createNote(id: 'note-1', title: 'Docker Notes', content: 'body'))
        .called(1);
    expect(await queue.pendingEntries(), isEmpty);
    final row = await local.findById('note-1');
    expect(row!.syncStatus, 'synced');
  });

  test('a failing push keeps the entry queued and marks the item failed', () async {
    await local.upsert(LocalItemsCompanion.insert(
      id: 'note-1',
      userId: 'user-1',
      type: ItemType.note.dbValue,
      processingStatus: const Value('completed'),
      createdAt: DateTime(2026, 1, 1),
      syncStatus: const Value('pending'),
    ));
    await queue.enqueue(
      operationType: 'create_note',
      itemId: 'note-1',
      payload: {'title': 'x', 'content': 'y'},
    );
    when(() => remote.createNote(
          id: any(named: 'id'),
          title: any(named: 'title'),
          content: any(named: 'content'),
        )).thenThrow(Exception('network down'));

    await sync.syncNow();

    final pending = await queue.pendingEntries();
    expect(pending, hasLength(1));
    expect(pending.single.retryCount, 1);
    final row = await local.findById('note-1');
    expect(row!.syncStatus, 'failed');
  });

  test('pushes a queued create_url and triggers AI processing for it', () async {
    await local.upsert(LocalItemsCompanion.insert(
      id: 'link-1',
      userId: 'user-1',
      type: ItemType.url.dbValue,
      title: const Value('https://example.com/docker-guide'),
      sourceUrl: const Value('https://example.com/docker-guide'),
      processingStatus: const Value('pending'),
      createdAt: DateTime(2026, 1, 1),
      syncStatus: const Value('pending'),
    ));
    await queue.enqueue(
      operationType: 'create_url',
      itemId: 'link-1',
      payload: {'url': 'https://example.com/docker-guide'},
    );
    when(() => remote.createUrlItem(
          id: 'link-1',
          url: 'https://example.com/docker-guide',
        )).thenAnswer((_) async {});

    await sync.syncNow();

    verify(() => remote.createUrlItem(id: 'link-1', url: 'https://example.com/docker-guide'))
        .called(1);
    expect(await queue.pendingEntries(), isEmpty);
    final row = await local.findById('link-1');
    expect(row!.syncStatus, 'synced');
  });

  test('pushes a queued dismiss_duplicate', () async {
    await local.upsert(LocalItemsCompanion.insert(
      id: 'item-1',
      userId: 'user-1',
      type: ItemType.note.dbValue,
      processingStatus: const Value('completed'),
      createdAt: DateTime(2026, 1, 1),
      duplicateOfItemId: const Value('item-0'),
      duplicateSimilarity: const Value(0.97),
      syncStatus: const Value('pending'),
    ));
    await queue.enqueue(
      operationType: 'dismiss_duplicate',
      itemId: 'item-1',
      payload: const {},
    );
    when(() => remote.dismissDuplicate('item-1')).thenAnswer((_) async {});

    await sync.syncNow();

    verify(() => remote.dismissDuplicate('item-1')).called(1);
    expect(await queue.pendingEntries(), isEmpty);
    final row = await local.findById('item-1');
    expect(row!.syncStatus, 'synced');
  });

  test('pulling remote state does not clobber a not-yet-synced local edit', () async {
    await local.upsert(LocalItemsCompanion.insert(
      id: 'note-1',
      userId: 'user-1',
      type: ItemType.note.dbValue,
      title: const Value('Local edit'),
      processingStatus: const Value('completed'),
      createdAt: DateTime(2026, 1, 1),
      noteContent: const Value('unsynced body'),
      syncStatus: const Value('pending'),
    ));
    await queue.enqueue(
      operationType: 'update_note',
      itemId: 'note-1',
      payload: {'title': 'Local edit', 'content': 'unsynced body'},
    );
    when(() => remote.fetchAllRows()).thenAnswer((_) async => [
          {
            'id': 'note-1',
            'type': 'note',
            'title': 'Stale server title',
            'description': null,
            'original_filename': null,
            'mime_type': null,
            'storage_path': null,
            'processing_status': 'completed',
            'favorite': false,
            'created_at': DateTime(2026, 1, 1).toIso8601String(),
          }
        ]);
    when(() => remote.updateNote(
          itemId: 'note-1',
          title: 'Local edit',
          content: 'unsynced body',
        )).thenAnswer((_) async {});

    await sync.syncNow();

    final row = await local.findById('note-1');
    expect(row!.title, 'Local edit'); // not overwritten by the stale pull
  });

  group('collections', () {
    test('pushes a queued create_collection and marks it synced', () async {
      await localCollections.upsert(LocalCollectionsCompanion.insert(
        id: 'coll-1',
        userId: 'user-1',
        name: 'Docker stuff',
        createdAt: DateTime(2026, 1, 1),
        syncStatus: const Value('pending'),
      ));
      await queue.enqueue(
        operationType: 'create_collection',
        itemId: 'coll-1',
        payload: {'name': 'Docker stuff', 'isSmart': false},
      );
      when(() => remoteCollections.createCollection(
            id: 'coll-1',
            name: 'Docker stuff',
            isSmart: false,
          )).thenAnswer((_) async {});

      await sync.syncNow();

      verify(() => remoteCollections.createCollection(
            id: 'coll-1',
            name: 'Docker stuff',
            isSmart: false,
          )).called(1);
      expect(await queue.pendingEntries(), isEmpty);
      final ids = await localCollections.allIds('user-1');
      expect(ids, contains('coll-1'));
    });

    test('a failing create_collection push keeps the entry queued and marks it failed', () async {
      await localCollections.upsert(LocalCollectionsCompanion.insert(
        id: 'coll-1',
        userId: 'user-1',
        name: 'Docker stuff',
        createdAt: DateTime(2026, 1, 1),
        syncStatus: const Value('pending'),
      ));
      await queue.enqueue(
        operationType: 'create_collection',
        itemId: 'coll-1',
        payload: {'name': 'Docker stuff', 'isSmart': false},
      );
      when(() => remoteCollections.createCollection(
            id: any(named: 'id'),
            name: any(named: 'name'),
            isSmart: any(named: 'isSmart'),
          )).thenThrow(Exception('network down'));

      await sync.syncNow();

      final pending = await queue.pendingEntries();
      expect(pending, hasLength(1));
    });

    test('pushes a queued add_to_collection', () async {
      await localCollections.addItem('coll-1', 'item-1', syncStatus: 'pending');
      await queue.enqueue(
        operationType: 'add_to_collection',
        itemId: 'coll-1',
        payload: {'itemId': 'item-1'},
      );
      when(() => remoteCollections.addItemToCollection(collectionId: 'coll-1', itemId: 'item-1'))
          .thenAnswer((_) async {});

      await sync.syncNow();

      verify(() => remoteCollections.addItemToCollection(collectionId: 'coll-1', itemId: 'item-1'))
          .called(1);
      expect(await queue.pendingEntries(), isEmpty);
    });

    test('pushes a queued remove_from_collection', () async {
      await queue.enqueue(
        operationType: 'remove_from_collection',
        itemId: 'coll-1',
        payload: {'itemId': 'item-1'},
      );
      when(() => remoteCollections.removeItemFromCollection(
            collectionId: 'coll-1',
            itemId: 'item-1',
          )).thenAnswer((_) async {});

      await sync.syncNow();

      verify(() => remoteCollections.removeItemFromCollection(
            collectionId: 'coll-1',
            itemId: 'item-1',
          )).called(1);
      expect(await queue.pendingEntries(), isEmpty);
    });

    test('pushes a queued delete_collection', () async {
      await queue.enqueue(operationType: 'delete_collection', itemId: 'coll-1', payload: const {});
      when(() => remoteCollections.deleteCollection('coll-1')).thenAnswer((_) async {});

      await sync.syncNow();

      verify(() => remoteCollections.deleteCollection('coll-1')).called(1);
      expect(await queue.pendingEntries(), isEmpty);
    });

    test('pulling remote collections does not clobber a not-yet-synced rename', () async {
      await localCollections.upsert(LocalCollectionsCompanion.insert(
        id: 'coll-1',
        userId: 'user-1',
        name: 'Renamed locally',
        createdAt: DateTime(2026, 1, 1),
        syncStatus: const Value('pending'),
      ));
      await queue.enqueue(
        operationType: 'rename_collection',
        itemId: 'coll-1',
        payload: {'name': 'Renamed locally'},
      );
      when(() => remoteCollections.fetchAllRows()).thenAnswer((_) async => [
            {
              'id': 'coll-1',
              'name': 'Stale server name',
              'is_smart': false,
              'created_at': DateTime(2026, 1, 1).toIso8601String(),
            }
          ]);
      when(() => remoteCollections.renameCollection('coll-1', 'Renamed locally'))
          .thenAnswer((_) async {});

      await sync.syncNow();

      final rows = await db.select(db.localCollections).get();
      expect(rows.single.name, 'Renamed locally'); // not overwritten by the stale pull
    });

    test('pulling remote membership drops a stale local row and adds a new one', () async {
      // A membership Supabase no longer has (removed elsewhere) — should
      // be dropped by the pull, since nothing has it queued.
      await localCollections.addItem('coll-1', 'stale-item', syncStatus: 'synced');
      when(() => remoteCollections.fetchAllRows()).thenAnswer((_) async => [
            {
              'id': 'coll-1',
              'name': 'A collection',
              'is_smart': false,
              'created_at': DateTime(2026, 1, 1).toIso8601String(),
            }
          ]);
      when(() => remoteCollections.fetchAllItemRows(['coll-1'])).thenAnswer((_) async => [
            {
              'collection_id': 'coll-1',
              'item_id': 'new-item',
              'added_at': DateTime(2026, 1, 2).toIso8601String(),
            }
          ]);

      await sync.syncNow();

      final memberships = await localCollections.allMemberships();
      expect(memberships, [('coll-1', 'new-item')]);
    });
  });
}
