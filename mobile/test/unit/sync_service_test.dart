import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesearch/core/database/app_database.dart';
import 'package:lifesearch/core/error/failure.dart';
import 'package:lifesearch/features/item/data/local/item_local_data_source.dart';
import 'package:lifesearch/features/item/data/local/sync_queue_data_source.dart';
import 'package:lifesearch/features/item/data/remote/ai_processing_trigger.dart';
import 'package:lifesearch/features/item/data/remote/remote_item_data_source.dart';
import 'package:lifesearch/features/item/data/sync/sync_service.dart';
import 'package:lifesearch/features/item/domain/entities/item.dart';
import 'package:mocktail/mocktail.dart';

class _MockRemote extends Mock implements RemoteItemDataSource {}

void main() {
  late AppDatabase db;
  late ItemLocalDataSource local;
  late SyncQueueDataSource queue;
  late _MockRemote remote;
  late SyncService sync;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    local = ItemLocalDataSource(db);
    queue = SyncQueueDataSource(db);
    remote = _MockRemote();
    when(() => remote.userId).thenReturn('user-1');
    when(() => remote.fetchAllRows()).thenAnswer((_) async => []);
    // BACKEND_URL unset -> null Dio -> triggerProcessing() is a no-op.
    sync = SyncService(
      local: local,
      remote: remote,
      queue: queue,
      aiTrigger: AiProcessingTrigger(null),
    );
  });

  tearDown(() => db.close());

  test('does nothing when nobody is signed in', () async {
    when(() => remote.userId).thenThrow(const AuthFailure('no session'));

    await sync.syncNow();

    verifyNever(() => remote.fetchAllRows());
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
}
