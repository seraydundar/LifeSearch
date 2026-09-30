import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:lifesearch/core/database/app_database.dart';
import 'package:lifesearch/core/sync/sync_service.dart';
import 'package:lifesearch/features/collections/data/local/collection_local_data_source.dart';
import 'package:lifesearch/features/collections/data/remote/remote_collection_data_source.dart';
import 'package:lifesearch/features/item/data/local/item_local_data_source.dart';
import 'package:lifesearch/features/item/data/local/sync_queue_data_source.dart';
import 'package:lifesearch/features/item/data/remote/ai_processing_trigger.dart';
import 'package:lifesearch/features/item/data/remote/remote_item_data_source.dart';
import 'package:lifesearch/features/item/data/repositories/offline_item_repository.dart';
import 'package:lifesearch/features/item/domain/entities/item.dart';

/// Stands in for `RemoteItemDataSource` in these tests — only `userId`,
/// `fetchById` and `uploadFileBytes` are ever exercised by
/// `OfflineItemRepository`, the rest is never called. Same subclassing
/// pattern as `item_providers_account_switch_test.dart`'s
/// `_AccountAwareRemoteItemDataSource`.
class _FakeRemoteItemDataSource extends RemoteItemDataSource {
  _FakeRemoteItemDataSource(super.client);

  Item? itemToReturn;
  Object? error;
  int fetchByIdCallCount = 0;
  Object? uploadError;
  int uploadFileBytesCallCount = 0;

  @override
  String get userId => 'user-a';

  @override
  Future<Item?> fetchById(String itemId) async {
    fetchByIdCallCount++;
    if (error != null) throw error!;
    return itemToReturn;
  }

  @override
  Future<void> uploadFileBytes({
    required String id,
    required Uint8List bytes,
    required String originalFilename,
    required String mimeType,
    required ItemType type,
    int? fileSizeBytes,
  }) async {
    uploadFileBytesCallCount++;
    if (uploadError != null) throw uploadError!;
  }
}

void main() {
  late AppDatabase db;
  late ItemLocalDataSource local;
  late SyncQueueDataSource queue;
  late _FakeRemoteItemDataSource remote;
  late OfflineItemRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    local = ItemLocalDataSource(db);
    queue = SyncQueueDataSource(db);
    remote = _FakeRemoteItemDataSource(SupabaseClient('https://example.invalid', 'dummy-anon-key'));
    repo = OfflineItemRepository(
      local: local,
      remote: remote,
      queue: queue,
      syncService: SyncService(
        local: local,
        remote: remote,
        localCollections: CollectionLocalDataSource(db),
        remoteCollections: RemoteCollectionDataSource(
          SupabaseClient('https://example.invalid', 'dummy-anon-key'),
        ),
        queue: queue,
        aiTrigger: AiProcessingTrigger(null),
      ),
    );
  });

  tearDown(() => db.close());

  // P2-09 (docs/requirements-audit-2026-09-13.md): findById used to look
  // only at the local cache — a genuinely new item on another device (or
  // one a search/RAG/related result surfaced before this device's own
  // sync pulled it in) could never resolve to more than a trimmed
  // stand-in.
  group('findById remote fallback (P2-09)', () {
    test('resolves from the remote when not cached locally', () async {
      remote.itemToReturn = Item(
        id: 'item-1',
        type: ItemType.pdf,
        title: 'Remote Only',
        processingStatus: 'completed',
        favorite: false,
        createdAt: DateTime(2026, 1, 1),
      );

      final result = await repo.findById('item-1');

      expect(result?.title, 'Remote Only');
      expect(remote.fetchByIdCallCount, 1);
    });

    test('caches the remote result locally so the next lookup needs no round trip', () async {
      remote.itemToReturn = Item(
        id: 'item-1',
        type: ItemType.pdf,
        title: 'Remote Only',
        processingStatus: 'completed',
        favorite: false,
        createdAt: DateTime(2026, 1, 1),
      );

      await repo.findById('item-1');
      remote.itemToReturn = null; // the remote is now unreachable/empty
      final second = await repo.findById('item-1');

      expect(second?.title, 'Remote Only'); // served from the local cache
      expect(remote.fetchByIdCallCount, 1); // never asked the remote a second time
    });

    test('never asks the remote when the item is already cached locally', () async {
      await local.upsert(LocalItemsCompanion.insert(
        id: 'item-1',
        userId: 'user-a',
        type: 'note',
        title: const Value('Local Item'),
        createdAt: DateTime(2026, 1, 1),
      ));

      final result = await repo.findById('item-1');

      expect(result?.id, 'item-1');
      expect(remote.fetchByIdCallCount, 0);
    });

    test('returns null, not an exception, when the remote genuinely has nothing', () async {
      remote.itemToReturn = null;

      expect(await repo.findById('does-not-exist'), isNull);
    });

    test('returns null, not an exception, when offline', () async {
      remote.error = Exception('no connection');

      expect(await repo.findById('item-1'), isNull);
    });
  });

  // P3 (docs/requirements-audit-2026-09-13.md, "Platformlar"): web's
  // file_picker only ever gives bytes, never a real filesystem path —
  // uploadFileBytes() is the bytes-based counterpart to uploadFile(),
  // deliberately with no offline queue (see its own docstring).
  group('uploadFileBytes (P3)', () {
    test('uploads immediately and marks the local row synced, not queued', () async {
      final item = await repo.uploadFileBytes(
        bytes: Uint8List.fromList([1, 2, 3]),
        originalFilename: 'photo.png',
        mimeType: 'image/png',
        type: ItemType.image,
      );

      expect(remote.uploadFileBytesCallCount, 1);
      final local = await repo.findById(item.id);
      expect(local?.processingStatus, 'pending'); // still awaits AI processing
      expect(await queue.pendingEntries('user-a'), isEmpty);
    });

    test('the remote call failing surfaces the error directly, no retry queued', () async {
      remote.uploadError = Exception('network down');

      await expectLater(
        repo.uploadFileBytes(
          bytes: Uint8List.fromList([1, 2, 3]),
          originalFilename: 'photo.png',
          mimeType: 'image/png',
          type: ItemType.image,
        ),
        throwsException,
      );
      expect(await queue.pendingEntries('user-a'), isEmpty);
    });
  });
}
