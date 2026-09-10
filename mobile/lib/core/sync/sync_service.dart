import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;

import '../../features/collections/data/local/collection_local_data_source.dart';
import '../../features/collections/data/remote/remote_collection_data_source.dart';
import '../../features/item/data/local/item_local_data_source.dart';
import '../../features/item/data/local/sync_queue_data_source.dart';
import '../../features/item/data/remote/ai_processing_trigger.dart';
import '../../features/item/data/remote/remote_item_data_source.dart';
import '../../features/item/domain/entities/item.dart';
import '../database/app_database.dart';
import '../error/failure.dart';

/// Upload item types the backend's AI pipeline actually supports for the
/// `upload_file` op — see backend/app/services/processing_pipeline.py
/// SUPPORTED_TYPES. `create_url` items are triggered unconditionally
/// instead (see `_shouldTriggerAi`), since a link has no upload step.
const _aiSupportedUploadTypes = {'pdf', 'image', 'screenshot', 'audio', 'document'};

/// Sync-queue operation types that target a collection itself (as opposed
/// to an item, or a collection's membership). Kept as a Set rather than a
/// per-case check so `_flushQueue`'s post-switch bookkeeping only needs one
/// membership test to know which local data source (and which id) a given
/// queue entry's `itemId` column actually refers to.
const _collectionOps = {'create_collection', 'rename_collection', 'delete_collection'};

/// Operation types for a (collectionId, itemId) membership row — for
/// these, the queue's `itemId` column holds the *collection* id, and the
/// actual item id lives in the payload (see `OfflineCollectionRepository`).
const _membershipOps = {'add_to_collection', 'remove_from_collection'};

/// Bridges the local cache and Supabase in both directions, for both items
/// and collections (they share one `sync_queue` table — see
/// `SyncQueueEntries` — so one coordinator has to own draining it; two
/// independent services would race and silently drop each other's
/// entries, since an unrecognized `operationType` is dropped rather than
/// retried):
///  - pulls the server's current state into the local cache (skipping
///    anything that has a not-yet-synced local edit, so it doesn't get
///    clobbered)
///  - pushes queued local writes to Supabase, oldest first
///
/// Framework-agnostic on purpose (no Riverpod `Ref` here) so it's easy to
/// unit-test with fakes; the Riverpod provider wires it up to connectivity
/// and auth-state changes.
class SyncService {
  SyncService({
    required ItemLocalDataSource local,
    required RemoteItemDataSource remote,
    required CollectionLocalDataSource localCollections,
    required RemoteCollectionDataSource remoteCollections,
    required SyncQueueDataSource queue,
    required AiProcessingTrigger aiTrigger,
    Duration pollInterval = const Duration(seconds: 5),
    int maxPollAttempts = 12,
  })  : _local = local,
        _remote = remote,
        _localCollections = localCollections,
        _remoteCollections = remoteCollections,
        _queue = queue,
        _aiTrigger = aiTrigger,
        _pollInterval = pollInterval,
        _maxPollAttempts = maxPollAttempts,
        _pollAttemptsLeft = maxPollAttempts;

  final ItemLocalDataSource _local;
  final RemoteItemDataSource _remote;
  final CollectionLocalDataSource _localCollections;
  final RemoteCollectionDataSource _remoteCollections;
  final SyncQueueDataSource _queue;
  final AiProcessingTrigger _aiTrigger;
  final Duration _pollInterval;
  final int _maxPollAttempts;

  bool _isSyncing = false;
  bool _syncAgain = false;
  Timer? _pollTimer;
  int _pollAttemptsLeft;

  /// Fire-and-forget: call after any local mutation or connectivity/auth
  /// change. Coalesces overlapping calls into a single extra run instead of
  /// running concurrently.
  void syncSoon() {
    if (_isSyncing) {
      _syncAgain = true;
      return;
    }
    unawaited(syncNow());
  }

  Future<void> syncNow() async {
    if (_isSyncing) {
      _syncAgain = true;
      return;
    }
    _isSyncing = true;
    try {
      final userId = _currentUserIdOrNull();
      if (userId == null) return; // not signed in yet — nothing to sync

      await _pullRemote(userId);
      await _pullRemoteCollections(userId);
      await _flushQueue(userId);
      await _scheduleNextPollIfNeeded(userId);
    } catch (_) {
      // Best-effort: a network blip here shouldn't crash the app. The next
      // connectivity change or mutation calls syncSoon() again.
    } finally {
      _isSyncing = false;
      if (_syncAgain) {
        _syncAgain = false;
        unawaited(syncNow());
      }
    }
  }

  /// The only way `processing`/`completed`/`failed` reaches this device
  /// today — there's no Supabase Realtime channel for it. Rather than
  /// leaving an item's status stale until the user backgrounds the app,
  /// edits something, or the network bounces (whichever of `syncSoon()`'s
  /// other callers happens to fire next), this keeps re-pulling every
  /// `_pollInterval` for as long as *this account* has something still
  /// `pending`/`processing` — and stops the moment it doesn't, so a quiet
  /// library never polls.
  ///
  /// Capped at `_maxPollAttempts` (default 12, i.e. ~1 minute at the
  /// default interval): plenty for how long AI processing actually takes
  /// in practice (seconds for a note/URL, tens of seconds for a PDF/image/
  /// audio file). A job that's still not done after that either finishes
  /// quietly and shows up next time something else triggers a sync, or is
  /// one `syncNow()` will never resolve on its own anyway (an orphaned job
  /// from a backend restart — see `job_recovery.py` on the backend side) —
  /// polling it forever wouldn't help either case, only drain battery.
  Future<void> _scheduleNextPollIfNeeded(String userId) async {
    _pollTimer?.cancel();
    _pollTimer = null;
    if (_pollAttemptsLeft <= 0) return;
    if (!await _local.hasUnfinishedProcessing(userId)) {
      _pollAttemptsLeft = _maxPollAttempts; // idle again — reset for next time
      return;
    }
    _pollAttemptsLeft--;
    _pollTimer = Timer(_pollInterval, syncSoon);
  }

  /// Cancels any pending poll — call when whatever owns this
  /// `SyncService` is itself being torn down (see `syncServiceProvider`),
  /// so a stray `Timer` never outlives it.
  void dispose() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  String? _currentUserIdOrNull() {
    try {
      return _remote.userId;
    } on AuthFailure {
      return null;
    }
  }

  Future<void> _pullRemote(String userId) async {
    final rows = await _remote.fetchAllRows();
    final pendingIds = (await _queue.pendingEntries(userId)).map((e) => e.itemId).toSet();

    final remoteIds = <String>{for (final row in rows) row['id'] as String};
    // A local edit is still queued for these — don't overwrite them.
    final rowsToUpsert = rows.where((row) => !pendingIds.contains(row['id'] as String)).toList();

    // Every note's content fetched as one concurrent batch instead of one
    // round trip at a time inside the loop below — a library with many
    // notes used to pull them in strictly sequentially. Still one extra
    // request per note (no backend join yet — fine at demo scale, worth
    // revisiting if libraries grow large), just no longer paid for one
    // after another.
    final noteContents = await Future.wait(rowsToUpsert.map((row) {
      return row['type'] == 'note'
          ? _remote.fetchNoteContent(row['id'] as String)
          : Future<String?>.value();
    }));

    for (var i = 0; i < rowsToUpsert.length; i++) {
      final row = rowsToUpsert[i];
      final id = row['id'] as String;
      await _local.upsert(LocalItemsCompanion.insert(
        id: id,
        userId: userId,
        type: row['type'] as String,
        title: Value(row['title'] as String?),
        description: Value(row['description'] as String?),
        originalFilename: Value(row['original_filename'] as String?),
        mimeType: Value(row['mime_type'] as String?),
        storagePath: Value(row['storage_path'] as String?),
        sourceUrl: Value(row['source_url'] as String?),
        processingStatus: Value(row['processing_status'] as String? ?? 'pending'),
        favorite: Value(row['favorite'] as bool? ?? false),
        createdAt: DateTime.parse(row['created_at'] as String),
        noteContent: Value(noteContents[i]),
        duplicateOfItemId: Value(row['duplicate_of_item_id'] as String?),
        duplicateSimilarity: Value((row['duplicate_similarity'] as num?)?.toDouble()),
        duplicateDismissed: Value(row['duplicate_dismissed'] as bool? ?? false),
        latitude: Value((row['latitude'] as num?)?.toDouble()),
        longitude: Value((row['longitude'] as num?)?.toDouble()),
        capturedAt: Value(
          row['captured_at'] == null ? null : DateTime.parse(row['captured_at'] as String),
        ),
        fileSizeBytes: Value((row['file_size_bytes'] as num?)?.toInt()),
        syncStatus: const Value('synced'),
      ));
    }

    // Drop local rows that no longer exist on the server (deleted from
    // another device) — but never a row still waiting to be *created*.
    final localIds = await _local.allIds(userId);
    final staleIds = localIds.where((id) => !remoteIds.contains(id) && !pendingIds.contains(id));
    if (staleIds.isNotEmpty) await _local.deleteMany(staleIds.toList());
  }

  Future<void> _pullRemoteCollections(String userId) async {
    final pending = await _queue.pendingEntries(userId);
    final pendingCollectionIds =
        pending.where((e) => _collectionOps.contains(e.operationType)).map((e) => e.itemId).toSet();
    final pendingMemberships = pending
        .where((e) => _membershipOps.contains(e.operationType))
        .map((e) => (e.itemId, jsonDecode(e.payload)['itemId'] as String))
        .toSet();

    final rows = await _remoteCollections.fetchAllRows();
    final remoteIds = <String>{};
    for (final row in rows) {
      final id = row['id'] as String;
      remoteIds.add(id);
      if (pendingCollectionIds.contains(id)) continue; // local edit still queued

      await _localCollections.upsert(LocalCollectionsCompanion.insert(
        id: id,
        userId: userId,
        name: row['name'] as String,
        isSmart: Value(row['is_smart'] as bool? ?? false),
        createdAt: DateTime.parse(row['created_at'] as String),
        syncStatus: const Value('synced'),
      ));
    }

    final localIds = await _localCollections.allIds(userId);
    final staleIds =
        localIds.where((id) => !remoteIds.contains(id) && !pendingCollectionIds.contains(id));
    if (staleIds.isNotEmpty) await _localCollections.deleteMany(staleIds.toList());

    // Membership rows — reconciled the same way, keyed on the pair rather
    // than a single id.
    final itemRows = await _remoteCollections.fetchAllItemRows(remoteIds.toList());
    final remoteMemberships = <(String, String)>{};
    for (final row in itemRows) {
      final pair = (row['collection_id'] as String, row['item_id'] as String);
      remoteMemberships.add(pair);
      if (pendingMemberships.contains(pair)) continue;
      await _localCollections.addItem(
        pair.$1,
        pair.$2,
        syncStatus: 'synced',
        addedAt: DateTime.parse(row['added_at'] as String),
      );
    }

    final localMemberships = await _localCollections.allMemberships();
    for (final pair in localMemberships) {
      if (!remoteMemberships.contains(pair) && !pendingMemberships.contains(pair)) {
        await _localCollections.removeItem(pair.$1, pair.$2);
      }
    }
  }

  Future<void> _flushQueue(String userId) async {
    for (final entry in await _queue.pendingEntries(userId)) {
      try {
        final payload = jsonDecode(entry.payload) as Map<String, dynamic>;
        switch (entry.operationType) {
          case 'create_note':
            await _remote.createNote(
              id: entry.itemId,
              title: payload['title'] as String,
              content: payload['content'] as String,
            );
          case 'update_note':
            await _remote.updateNote(
              itemId: entry.itemId,
              title: payload['title'] as String,
              content: payload['content'] as String,
            );
          case 'set_favorite':
            await _remote.setFavorite(entry.itemId, payload['favorite'] as bool);
          case 'dismiss_duplicate':
            await _remote.dismissDuplicate(entry.itemId);
          case 'delete_item':
            await _remote.deleteItem(
              itemId: entry.itemId,
              storagePath: payload['storagePath'] as String?,
            );
          case 'create_url':
            await _remote.createUrlItem(
              id: entry.itemId,
              url: payload['url'] as String,
            );
          case 'upload_file':
            await _remote.uploadFile(
              id: entry.itemId,
              localFilePath: payload['localFilePath'] as String,
              originalFilename: payload['originalFilename'] as String,
              mimeType: payload['mimeType'] as String,
              type: ItemTypeX.fromDbValue(payload['type'] as String),
              fileSizeBytes: (payload['fileSizeBytes'] as num?)?.toInt(),
            );
          case 'create_collection':
            await _remoteCollections.createCollection(
              id: entry.itemId,
              name: payload['name'] as String,
              isSmart: payload['isSmart'] as bool? ?? false,
            );
          case 'rename_collection':
            await _remoteCollections.renameCollection(entry.itemId, payload['name'] as String);
          case 'delete_collection':
            await _remoteCollections.deleteCollection(entry.itemId);
          case 'add_to_collection':
            await _remoteCollections.addItemToCollection(
              collectionId: entry.itemId,
              itemId: payload['itemId'] as String,
            );
          case 'remove_from_collection':
            await _remoteCollections.removeItemFromCollection(
              collectionId: entry.itemId,
              itemId: payload['itemId'] as String,
            );
          case 'trigger_ai':
            // Queued by `_triggerAi()` below (or `ItemRepository.retryProcessing()`)
            // when an earlier attempt couldn't reach the backend. Throwing
            // on failure — rather than swallowing again — lets this fall
            // into the same catch block as every other op, so it's kept
            // queued and retried with the usual `retryCount`/`lastError`
            // bookkeeping instead of silently disappearing a second time.
            if (!await _aiTrigger.triggerProcessing(entry.itemId)) {
              throw Exception('AI trigger did not reach the backend');
            }
          default:
            // Unknown op from a future app version — drop it rather than
            // retry forever.
            break;
        }
        await _queue.remove(entry.id);
        await _markSynced(entry.operationType, entry.itemId, payload);
        if (_shouldTriggerAi(entry.operationType, payload)) {
          await _triggerAi(userId, entry.itemId);
        }
      } catch (e) {
        await _queue.recordFailure(entry.id, e.toString());
        await _markFailed(entry.operationType, entry.itemId);
        // Keep processing the rest of the queue — one bad entry shouldn't
        // block every other pending change.
      }
    }
  }

  Future<void> _markSynced(
    String operationType,
    String queuedId,
    Map<String, dynamic> payload,
  ) async {
    if (operationType == 'trigger_ai') return; // no local row to touch — see _triggerAi()
    if (_membershipOps.contains(operationType)) {
      if (operationType == 'add_to_collection') {
        await _localCollections.markMembershipSynced(queuedId, payload['itemId'] as String);
      }
      // 'remove_from_collection': the local row is already gone — nothing
      // left to mark.
      return;
    }
    if (_collectionOps.contains(operationType)) {
      if (operationType != 'delete_collection') {
        await _localCollections.markSynced(queuedId);
      }
      return;
    }
    if (operationType != 'delete_item') {
      await _local.markSynced(queuedId);
    }
  }

  Future<void> _markFailed(String operationType, String queuedId) async {
    // Neither case has a local item/collection row to flag: `trigger_ai`
    // retries a side-effect on an item that already synced fine — marking
    // *it* as sync-failed would be wrong (its own data reached the server;
    // only the AI kickoff didn't).
    if (operationType == 'trigger_ai') return;
    if (_membershipOps.contains(operationType)) return; // nothing local to flag as failed
    if (_collectionOps.contains(operationType)) {
      await _localCollections.markFailed(queuedId);
      return;
    }
    await _local.markFailed(queuedId);
  }

  /// Best-effort but not silent: if the backend can't be reached right now,
  /// queues a `trigger_ai` retry — persisted in `sync_queue` (survives an
  /// app restart) and drained by every future `_flushQueue()` call, unlike
  /// the old fire-and-forget version, which just lost the attempt and left
  /// the item stuck in `pending` with no record anything had gone wrong.
  Future<void> _triggerAi(String userId, String itemId) async {
    final triggered = await _aiTrigger.triggerProcessing(itemId);
    if (!triggered) {
      await _queue.enqueue(
        userId: userId,
        operationType: 'trigger_ai',
        itemId: itemId,
        payload: const {},
      );
    }
  }

  bool _shouldTriggerAi(String operationType, Map<String, dynamic> payload) {
    return switch (operationType) {
      'create_note' || 'update_note' || 'create_url' => true,
      'upload_file' => _aiSupportedUploadTypes.contains(payload['type']),
      _ => false,
    };
  }
}
