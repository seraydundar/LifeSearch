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
import 'sync_cursor_storage.dart';

/// Upload types the backend's AI pipeline supports for `upload_file`; also used by
/// `OfflineItemRepository.uploadFileBytes`'s queue-bypassing upload path, as one source of truth.
const aiSupportedUploadTypes = {'pdf', 'image', 'screenshot', 'audio', 'document'};

/// Sync-queue ops that target a collection itself (vs. an item or a membership row).
const _collectionOps = {'create_collection', 'rename_collection', 'delete_collection'};

/// Membership ops where the queue's `itemId` column actually holds the *collection* id,
/// and the real item id lives in the payload.
const _membershipOps = {'add_to_collection', 'remove_from_collection'};

/// Bridges the local cache and Supabase for both items and collections (one shared `sync_queue`
/// table needs one coordinator, or two services would race). Framework-agnostic (no Riverpod `Ref`)
/// for easy unit testing; the Riverpod provider wires it to connectivity/auth-state changes.
class SyncService {
  SyncService({
    required ItemLocalDataSource local,
    required RemoteItemDataSource remote,
    required CollectionLocalDataSource localCollections,
    required RemoteCollectionDataSource remoteCollections,
    required SyncQueueDataSource queue,
    required AiProcessingTrigger aiTrigger,
    SyncCursorStorage? syncCursor,
    Duration pollInterval = const Duration(seconds: 5),
    int maxPollAttempts = 12,
  })  : _local = local,
        _remote = remote,
        _localCollections = localCollections,
        _remoteCollections = remoteCollections,
        _queue = queue,
        _aiTrigger = aiTrigger,
        _syncCursor = syncCursor ?? SyncCursorStorage(),
        _pollInterval = pollInterval,
        _maxPollAttempts = maxPollAttempts,
        _pollAttemptsLeft = maxPollAttempts;

  final ItemLocalDataSource _local;
  final RemoteItemDataSource _remote;
  final CollectionLocalDataSource _localCollections;
  final RemoteCollectionDataSource _remoteCollections;
  final SyncQueueDataSource _queue;
  final AiProcessingTrigger _aiTrigger;
  final SyncCursorStorage _syncCursor;
  final Duration _pollInterval;
  final int _maxPollAttempts;

  bool _isSyncing = false;
  bool _syncAgain = false;
  Timer? _pollTimer;
  int _pollAttemptsLeft;
  // Items pending/processing as of the last poll; lets _scheduleNextPollIfNeeded tell a
  // still-stuck job apart from a newly-appeared one.
  Set<String> _pollingItemIds = {};

  /// Fire-and-forget; coalesces overlapping calls into one extra run instead of running concurrently.
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
      // Best-effort: a network blip shouldn't crash the app; syncSoon() gets called again later.
    } finally {
      _isSyncing = false;
      if (_syncAgain) {
        _syncAgain = false;
        unawaited(syncNow());
      }
    }
  }

  /// Polls while this account has anything pending/processing (no Realtime channel for status;
  /// stops once idle). Budget is per pending-stretch, not per-instance: tracking which ids are
  /// pending (not just whether any are) resets `_pollAttemptsLeft` when a new id appears, so one
  /// permanently-stuck job can't exhaust the budget for every job after it.
  Future<void> _scheduleNextPollIfNeeded(String userId) async {
    _pollTimer?.cancel();
    _pollTimer = null;

    final pendingIds = await _local.unfinishedProcessingIds(userId);
    if (pendingIds.isEmpty) {
      _pollAttemptsLeft = _maxPollAttempts; // idle again — reset for next time
      _pollingItemIds = {};
      return;
    }
    if (!pendingIds.every(_pollingItemIds.contains)) {
      _pollAttemptsLeft = _maxPollAttempts; // at least one id is new since last check
    }
    _pollingItemIds = pendingIds;

    if (_pollAttemptsLeft <= 0) return; // this stretch already had its fair shot
    _pollAttemptsLeft--;
    _pollTimer = Timer(_pollInterval, syncSoon);
  }

  /// Cancels any pending poll; call when whatever owns this `SyncService` is torn down.
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
    // `since` is null only on this account's first sync on this device; after that, incremental.
    final since = await _syncCursor.read(userId);
    final rows = await _remote.fetchAllRows(since: since);
    final pendingIds = (await _queue.pendingEntries(userId)).map((e) => e.itemId).toSet();

    final changedIds = <String>{for (final row in rows) row['id'] as String};
    // Incremental `rows` are only the changed ones, so deletion detection needs the full id set
    // from a separate request; a first sync's `rows` already IS the full set.
    final remoteIds = since == null ? changedIds : await _remote.fetchAllIds();

    // A local edit is still queued for these — don't overwrite them.
    final rowsToUpsert = rows.where((row) => !pendingIds.contains(row['id'] as String)).toList();

    // item_contents.raw_text fetched in one bulk request (keyed by item_id) and reused for both
    // extractedText and noteContent (a note's content IS its raw_text) rather than a separate
    // per-note fetch; scoped to rowsToUpsert's ids on an incremental sync.
    final contentScope =
        since == null ? null : rowsToUpsert.map((row) => row['id'] as String).toList();
    Map<String, String?> extractedTextByItemId;
    if (contentScope != null && contentScope.isEmpty) {
      extractedTextByItemId = const {};
    } else {
      final contentRows = await _remote.fetchAllItemContentRows(itemIds: contentScope);
      extractedTextByItemId = {
        for (final row in contentRows) row['item_id'] as String: row['raw_text'] as String?,
      };
    }

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
        noteContent: Value(row['type'] == 'note' ? extractedTextByItemId[id] : null),
        duplicateOfItemId: Value(row['duplicate_of_item_id'] as String?),
        duplicateSimilarity: Value((row['duplicate_similarity'] as num?)?.toDouble()),
        duplicateDismissed: Value(row['duplicate_dismissed'] as bool? ?? false),
        latitude: Value((row['latitude'] as num?)?.toDouble()),
        longitude: Value((row['longitude'] as num?)?.toDouble()),
        capturedAt: Value(
          row['captured_at'] == null ? null : DateTime.parse(row['captured_at'] as String),
        ),
        fileSizeBytes: Value((row['file_size_bytes'] as num?)?.toInt()),
        private: Value(row['private'] as bool? ?? false),
        extractedText: Value(extractedTextByItemId[id]),
        syncStatus: const Value('synced'),
      ));
    }

    // Drop local rows no longer on the server (deleted elsewhere) — never a row still queued to be created.
    final localIds = await _local.allIds(userId);
    final staleIds = localIds.where((id) => !remoteIds.contains(id) && !pendingIds.contains(id));
    if (staleIds.isNotEmpty) await _local.deleteMany(staleIds.toList());

    // replaceTags's first arg is also its delete scope, so it must match tagRows' fetch scope
    // exactly (changedIds on incremental) — passing the full localIds here would wipe unchanged
    // items' tags with nothing fetched to reinsert them.
    final tagDeleteScope = since == null ? localIds : changedIds.toList();
    if (tagDeleteScope.isNotEmpty) {
      final tagRows = await _remote.fetchAllItemTagRows(
        itemIds: since == null ? null : tagDeleteScope,
      );
      await _local.replaceTags(tagDeleteScope, [
        for (final row in tagRows)
          (
            itemId: row['item_id'] as String,
            name: (row['tags'] as Map<String, dynamic>)['name'] as String,
          ),
      ]);
    }

    // Cursor is the latest updated_at actually seen, not DateTime.now() — the next sync compares
    // against a server-side column, so this device's clock can't be the source of truth.
    if (rows.isNotEmpty) {
      final latestUpdatedAt = rows
          .map((row) => DateTime.parse(row['updated_at'] as String))
          .reduce((a, b) => a.isAfter(b) ? a : b);
      await _syncCursor.write(userId, latestUpdatedAt);
    }
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

    // Membership rows reconciled the same way, keyed on the pair rather than a single id.
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

    final localMemberships = await _localCollections.allMemberships(userId);
    for (final pair in localMemberships) {
      if (!remoteMemberships.contains(pair) && !pendingMemberships.contains(pair)) {
        await _localCollections.removeItem(pair.$1, pair.$2);
      }
    }
  }

  Future<void> _flushQueue(String userId) async {
    for (final entry in await _queue.pendingEntries(userId)) {
      // Each write below reads the live Supabase session, not the userId this run was scoped to —
      // stop here if the account switched mid-flush, so A's remaining writes don't go out under B's
      // session. Doesn't protect a request already in flight (same residual-gap tradeoff as
      // url_service.py's documented DNS-rebinding gap).
      if (_currentUserIdOrNull() != userId) return;
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
          case 'set_private':
            await _remote.setPrivate(entry.itemId, payload['private'] as bool);
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
            // Throw on failure so this falls into the same catch block as every other op,
            // and gets retried via the usual retryCount/lastError bookkeeping.
            if (!await _aiTrigger.triggerProcessing(entry.itemId)) {
              throw Exception('AI trigger did not reach the backend');
            }
          default:
            // Unknown op from a future app version — drop rather than retry forever.
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
        // Keep going — one bad entry shouldn't block the rest of the queue.
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
      // 'remove_from_collection': the local row is already gone.
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
    // trigger_ai retries a side-effect on an item that already synced fine; marking it sync-failed would be wrong.
    if (operationType == 'trigger_ai') return;
    if (_membershipOps.contains(operationType)) return; // nothing local to flag as failed
    if (_collectionOps.contains(operationType)) {
      await _localCollections.markFailed(queuedId);
      return;
    }
    await _local.markFailed(queuedId);
  }

  /// Public wrapper for [_triggerAi]: used by `OfflineItemRepository.uploadFileBytes`'s web upload
  /// path, which bypasses `sync_queue` entirely and so never reaches `_flushQueue`'s own call to it.
  Future<void> triggerAiNow(String userId, String itemId) => _triggerAi(userId, itemId);

  /// If the backend can't be reached, queues a persisted `trigger_ai` retry rather than losing the attempt.
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
      'upload_file' => aiSupportedUploadTypes.contains(payload['type']),
      _ => false,
    };
  }
}
