import 'package:dio/dio.dart';
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

  tearDown(() {
    // Cancels any poll Timer syncNow() may have scheduled before the
    // 5-second default interval ever gets a chance to fire in the
    // background, past this test's own lifetime.
    sync.dispose();
    return db.close();
  });

  test('does nothing when nobody is signed in', () async {
    when(() => remote.userId).thenThrow(const AuthFailure('no session'));

    await sync.syncNow();

    verifyNever(() => remote.fetchAllRows());
    verifyNever(() => remoteCollections.fetchAllRows());
  });

  test(
      "a still-queued entry from a previous account is never flushed under "
      'a newly signed-in one, on the same device', () async {
    // user-1 creates a note offline...
    await local.upsert(LocalItemsCompanion.insert(
      id: 'note-1',
      userId: 'user-1',
      type: ItemType.note.dbValue,
      title: const Value('user-1\'s private note'),
      processingStatus: const Value('pending'),
      createdAt: DateTime(2026, 1, 1),
      noteContent: const Value('body'),
      syncStatus: const Value('pending'),
    ));
    await queue.enqueue(
      userId: 'user-1',
      operationType: 'create_note',
      itemId: 'note-1',
      payload: {'title': "user-1's private note", 'content': 'body'},
    );

    // ...then, before it ever syncs, a *different* account signs in on the
    // same device (the actual bug: SyncQueueEntries had no userId at all,
    // so this second sync pass would have pushed user-1's note under
    // user-2's session — see requirements doc, rule 14).
    when(() => remote.userId).thenReturn('user-2');

    await sync.syncNow();

    verifyNever(() => remote.createNote(
          id: any(named: 'id'),
          title: any(named: 'title'),
          content: any(named: 'content'),
        ));
    // Still sitting in the queue, untouched, waiting for user-1 to sign
    // back in — not silently dropped, and not pushed under user-2.
    expect(await queue.pendingEntries('user-1'), hasLength(1));
    expect(await queue.pendingEntries('user-2'), isEmpty);

    // When user-1 signs back in, their own pending note *does* flush
    // normally — this isn't a permanently stuck entry.
    when(() => remote.userId).thenReturn('user-1');
    when(() => remote.createNote(
          id: 'note-1',
          title: "user-1's private note",
          content: 'body',
        )).thenAnswer((_) async {});

    await sync.syncNow();

    verify(() => remote.createNote(
          id: 'note-1',
          title: "user-1's private note",
          content: 'body',
        )).called(1);
    expect(await queue.pendingEntries('user-1'), isEmpty);
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
      userId: 'user-1',
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
    expect(await queue.pendingEntries('user-1'), isEmpty);
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
      userId: 'user-1',
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

    final pending = await queue.pendingEntries('user-1');
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
      userId: 'user-1',
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
    expect(await queue.pendingEntries('user-1'), isEmpty);
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
      userId: 'user-1',
      operationType: 'dismiss_duplicate',
      itemId: 'item-1',
      payload: const {},
    );
    when(() => remote.dismissDuplicate('item-1')).thenAnswer((_) async {});

    await sync.syncNow();

    verify(() => remote.dismissDuplicate('item-1')).called(1);
    expect(await queue.pendingEntries('user-1'), isEmpty);
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
      userId: 'user-1',
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

  Map<String, dynamic> noteRow(String id, {String title = 'Untitled'}) => {
        'id': id,
        'type': 'note',
        'title': title,
        'description': null,
        'original_filename': null,
        'mime_type': null,
        'storage_path': null,
        'processing_status': 'completed',
        'favorite': false,
        'created_at': DateTime(2026, 1, 1).toIso8601String(),
      };

  test('pulling remote notes fetches and stores each one\'s content', () async {
    when(() => remote.fetchAllRows()).thenAnswer(
      (_) async => [noteRow('note-1', title: 'First'), noteRow('note-2', title: 'Second')],
    );
    when(() => remote.fetchNoteContent('note-1')).thenAnswer((_) async => 'body one');
    when(() => remote.fetchNoteContent('note-2')).thenAnswer((_) async => 'body two');

    await sync.syncNow();

    expect((await local.findById('note-1'))!.noteContent, 'body one');
    expect((await local.findById('note-2'))!.noteContent, 'body two');
  });

  test('pulling remote notes fetches their content concurrently, not one at a time', () async {
    // Regression guard: this used to await fetchNoteContent() inside the
    // per-row loop, so a library with N notes paid for N round trips in
    // series. If that ever comes back, active never exceeds 1 here.
    var active = 0;
    var maxActive = 0;
    when(() => remote.fetchNoteContent(any())).thenAnswer((invocation) async {
      active++;
      maxActive = active > maxActive ? active : maxActive;
      await Future<void>.delayed(Duration.zero); // yield so calls actually overlap
      active--;
      return 'content for ${invocation.positionalArguments[0]}';
    });
    when(() => remote.fetchAllRows()).thenAnswer(
      (_) async => [noteRow('note-1'), noteRow('note-2'), noteRow('note-3')],
    );

    await sync.syncNow();

    expect(maxActive, greaterThanOrEqualTo(2));
  });

  group('trigger_ai', () {
    test(
        "a create_url push whose AI trigger can't reach the backend queues a "
        'trigger_ai retry instead of losing the attempt', () async {
      // A real Dio configured with a bad/unreachable base URL — unlike the
      // suite's default `AiProcessingTrigger(null)`, this represents an
      // actual "backend is down right now" failure, not "AI isn't
      // configured at all".
      final failingDio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:1'));
      sync = SyncService(
        local: local,
        remote: remote,
        localCollections: localCollections,
        remoteCollections: remoteCollections,
        queue: queue,
        aiTrigger: AiProcessingTrigger(failingDio),
      );
      await local.upsert(LocalItemsCompanion.insert(
        id: 'link-1',
        userId: 'user-1',
        type: ItemType.url.dbValue,
        sourceUrl: const Value('https://example.com'),
        processingStatus: const Value('pending'),
        createdAt: DateTime(2026, 1, 1),
        syncStatus: const Value('pending'),
      ));
      await queue.enqueue(
        userId: 'user-1',
        operationType: 'create_url',
        itemId: 'link-1',
        payload: {'url': 'https://example.com'},
      );
      when(() => remote.createUrlItem(id: 'link-1', url: 'https://example.com'))
          .thenAnswer((_) async {});

      await sync.syncNow();

      // The create_url itself succeeded — it's gone, and the item shows
      // synced — only the AI kickoff is what's still pending.
      final row = await local.findById('link-1');
      expect(row!.syncStatus, 'synced');
      final pending = await queue.pendingEntries('user-1');
      expect(pending, hasLength(1));
      expect(pending.single.operationType, 'trigger_ai');
      expect(pending.single.itemId, 'link-1');
    });

    test('a trigger_ai retry that still fails stays queued with a bumped retry count',
        () async {
      final failingDio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:1'));
      sync = SyncService(
        local: local,
        remote: remote,
        localCollections: localCollections,
        remoteCollections: remoteCollections,
        queue: queue,
        aiTrigger: AiProcessingTrigger(failingDio),
      );
      await queue.enqueue(
        userId: 'user-1',
        operationType: 'trigger_ai',
        itemId: 'link-1',
        payload: const {},
      );

      await sync.syncNow();

      final pending = await queue.pendingEntries('user-1');
      expect(pending, hasLength(1));
      expect(pending.single.retryCount, 1);
      // Nothing local to have flagged failed — trigger_ai has no item/
      // collection row of its own to touch.
      expect(await local.findById('link-1'), null);
    });

    test('a trigger_ai retry that succeeds is removed from the queue', () async {
      await queue.enqueue(
        userId: 'user-1',
        operationType: 'trigger_ai',
        itemId: 'link-1',
        payload: const {},
      );
      // Default setup's aiTrigger is AiProcessingTrigger(null) -> always
      // reports success without making a real request.

      await sync.syncNow();

      expect(await queue.pendingEntries('user-1'), isEmpty);
    });
  });

  group('AI status polling', () {
    // No Supabase Realtime channel exists for `processing_status` yet —
    // this is the only thing that makes `completed`/`failed` show up
    // without the user backgrounding the app, editing something, or the
    // network bouncing. Each test builds its own SyncService with a tiny
    // pollInterval so it doesn't have to wait on the real 5s default.
    Map<String, dynamic> pendingRow(String status) => {
          'id': 'item-1',
          'type': 'note',
          'title': 'x',
          'description': null,
          'original_filename': null,
          'mime_type': null,
          'storage_path': null,
          'processing_status': status,
          'favorite': false,
          'created_at': DateTime(2026, 1, 1).toIso8601String(),
        };

    test('keeps re-syncing while an item is still pending, and stops once it '
        'turns up completed', () async {
      var status = 'pending';
      var fetchCount = 0;
      when(() => remote.fetchAllRows()).thenAnswer((_) async {
        fetchCount++;
        return [pendingRow(status)];
      });
      when(() => remote.fetchNoteContent(any())).thenAnswer((_) async => 'body');
      final pollingSync = SyncService(
        local: local,
        remote: remote,
        localCollections: localCollections,
        remoteCollections: remoteCollections,
        queue: queue,
        aiTrigger: AiProcessingTrigger(null),
        pollInterval: const Duration(milliseconds: 10),
        maxPollAttempts: 50, // comfortably more than this test needs
      );

      await pollingSync.syncNow();
      expect(fetchCount, 1);

      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(fetchCount, greaterThan(1)); // polled while still pending

      status = 'completed'; // ...the backend finished processing it
      await Future<void>.delayed(const Duration(milliseconds: 150));
      final countOnceCompleted = fetchCount;
      await Future<void>.delayed(const Duration(milliseconds: 150));
      // No growth after that — completed is terminal, nothing left to poll for.
      expect(fetchCount, countOnceCompleted);

      pollingSync.dispose();
    });

    test('never polls at all when nothing is pending to begin with', () async {
      var fetchCount = 0;
      when(() => remote.fetchAllRows()).thenAnswer((_) async {
        fetchCount++;
        return [pendingRow('completed')];
      });
      when(() => remote.fetchNoteContent(any())).thenAnswer((_) async => 'body');
      final pollingSync = SyncService(
        local: local,
        remote: remote,
        localCollections: localCollections,
        remoteCollections: remoteCollections,
        queue: queue,
        aiTrigger: AiProcessingTrigger(null),
        pollInterval: const Duration(milliseconds: 10),
      );

      await pollingSync.syncNow();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(fetchCount, 1); // the one call syncNow() itself made — no more

      pollingSync.dispose();
    });

    test('gives up after maxPollAttempts rather than polling a hung job forever',
        () async {
      var fetchCount = 0;
      when(() => remote.fetchAllRows()).thenAnswer((_) async {
        fetchCount++;
        return [pendingRow('pending')]; // never resolves
      });
      when(() => remote.fetchNoteContent(any())).thenAnswer((_) async => 'body');
      final pollingSync = SyncService(
        local: local,
        remote: remote,
        localCollections: localCollections,
        remoteCollections: remoteCollections,
        queue: queue,
        aiTrigger: AiProcessingTrigger(null),
        pollInterval: const Duration(milliseconds: 10),
        maxPollAttempts: 3,
      );

      await pollingSync.syncNow();
      // Initial call + at most 3 retries, with generous margin for the
      // real Timers involved — then it must plateau.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final total = fetchCount;
      expect(total, lessThanOrEqualTo(4)); // 1 initial + 3 polls, never more
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(fetchCount, total); // no further growth once attempts run out

      pollingSync.dispose();
    });
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
        userId: 'user-1',
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
      expect(await queue.pendingEntries('user-1'), isEmpty);
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
        userId: 'user-1',
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

      final pending = await queue.pendingEntries('user-1');
      expect(pending, hasLength(1));
    });

    test('pushes a queued add_to_collection', () async {
      await localCollections.addItem('coll-1', 'item-1', syncStatus: 'pending');
      await queue.enqueue(
        userId: 'user-1',
        operationType: 'add_to_collection',
        itemId: 'coll-1',
        payload: {'itemId': 'item-1'},
      );
      when(() => remoteCollections.addItemToCollection(collectionId: 'coll-1', itemId: 'item-1'))
          .thenAnswer((_) async {});

      await sync.syncNow();

      verify(() => remoteCollections.addItemToCollection(collectionId: 'coll-1', itemId: 'item-1'))
          .called(1);
      expect(await queue.pendingEntries('user-1'), isEmpty);
    });

    test('pushes a queued remove_from_collection', () async {
      await queue.enqueue(
        userId: 'user-1',
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
      expect(await queue.pendingEntries('user-1'), isEmpty);
    });

    test('pushes a queued delete_collection', () async {
      await queue.enqueue(userId: 'user-1', operationType: 'delete_collection', itemId: 'coll-1', payload: const {});
      when(() => remoteCollections.deleteCollection('coll-1')).thenAnswer((_) async {});

      await sync.syncNow();

      verify(() => remoteCollections.deleteCollection('coll-1')).called(1);
      expect(await queue.pendingEntries('user-1'), isEmpty);
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
        userId: 'user-1',
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
