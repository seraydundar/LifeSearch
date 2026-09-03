import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;

import '../../../../core/database/app_database.dart';
import '../../../../core/error/failure.dart';
import '../../domain/entities/item.dart';
import '../local/item_local_data_source.dart';
import '../local/sync_queue_data_source.dart';
import '../remote/ai_processing_trigger.dart';
import '../remote/remote_item_data_source.dart';

/// Operation types (and, for uploads, item types) the backend's Phase 4
/// pipeline actually supports — see backend/app/services/processing_pipeline.py
/// SUPPORTED_TYPES. Everything else (images today; audio/URL later) just
/// isn't wired up yet, so there's nothing to trigger.
const _aiSupportedUploadTypes = {'pdf'};

/// Bridges the local cache and Supabase in both directions:
///  - pulls the server's current state into `LocalItems` (skipping any item
///    that has a not-yet-synced local edit, so it doesn't get clobbered)
///  - pushes queued local writes to Supabase, oldest first
///
/// Framework-agnostic on purpose (no Riverpod `Ref` here) so it's easy to
/// unit-test with fakes; the Riverpod provider wires it up to connectivity
/// and auth-state changes.
class SyncService {
  SyncService({
    required ItemLocalDataSource local,
    required RemoteItemDataSource remote,
    required SyncQueueDataSource queue,
    required AiProcessingTrigger aiTrigger,
  })  : _local = local,
        _remote = remote,
        _queue = queue,
        _aiTrigger = aiTrigger;

  final ItemLocalDataSource _local;
  final RemoteItemDataSource _remote;
  final SyncQueueDataSource _queue;
  final AiProcessingTrigger _aiTrigger;

  bool _isSyncing = false;
  bool _syncAgain = false;

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
      await _flushQueue();
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

  String? _currentUserIdOrNull() {
    try {
      return _remote.userId;
    } on AuthFailure {
      return null;
    }
  }

  Future<void> _pullRemote(String userId) async {
    final rows = await _remote.fetchAllRows();
    final pendingIds = (await _queue.pendingEntries()).map((e) => e.itemId).toSet();

    final remoteIds = <String>{};
    for (final row in rows) {
      final id = row['id'] as String;
      remoteIds.add(id);
      if (pendingIds.contains(id)) continue; // a local edit is still queued — don't overwrite it

      String? noteContent;
      if (row['type'] == 'note') {
        // One extra round-trip per note. Fine at demo scale; worth folding
        // into fetchAllRows() with a join if libraries grow large.
        noteContent = await _remote.fetchNoteContent(id);
      }

      await _local.upsert(LocalItemsCompanion.insert(
        id: id,
        userId: userId,
        type: row['type'] as String,
        title: Value(row['title'] as String?),
        description: Value(row['description'] as String?),
        originalFilename: Value(row['original_filename'] as String?),
        mimeType: Value(row['mime_type'] as String?),
        storagePath: Value(row['storage_path'] as String?),
        processingStatus: Value(row['processing_status'] as String? ?? 'pending'),
        favorite: Value(row['favorite'] as bool? ?? false),
        createdAt: DateTime.parse(row['created_at'] as String),
        noteContent: Value(noteContent),
        syncStatus: const Value('synced'),
      ));
    }

    // Drop local rows that no longer exist on the server (deleted from
    // another device) — but never a row still waiting to be *created*.
    final localIds = await _local.allIds(userId);
    final staleIds = localIds.where((id) => !remoteIds.contains(id) && !pendingIds.contains(id));
    if (staleIds.isNotEmpty) await _local.deleteMany(staleIds.toList());
  }

  Future<void> _flushQueue() async {
    for (final entry in await _queue.pendingEntries()) {
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
          case 'delete_item':
            await _remote.deleteItem(
              itemId: entry.itemId,
              storagePath: payload['storagePath'] as String?,
            );
          case 'upload_file':
            await _remote.uploadFile(
              id: entry.itemId,
              localFilePath: payload['localFilePath'] as String,
              originalFilename: payload['originalFilename'] as String,
              mimeType: payload['mimeType'] as String,
              type: ItemTypeX.fromDbValue(payload['type'] as String),
            );
          default:
            // Unknown op from a future app version — drop it rather than
            // retry forever.
            break;
        }
        await _queue.remove(entry.id);
        if (entry.operationType != 'delete_item') {
          await _local.markSynced(entry.itemId);
        }
        if (_shouldTriggerAi(entry.operationType, payload)) {
          unawaited(_aiTrigger.triggerProcessing(entry.itemId));
        }
      } catch (e) {
        await _queue.recordFailure(entry.id, e.toString());
        await _local.markFailed(entry.itemId);
        // Keep processing the rest of the queue — one bad entry shouldn't
        // block every other pending change.
      }
    }
  }

  bool _shouldTriggerAi(String operationType, Map<String, dynamic> payload) {
    return switch (operationType) {
      'create_note' || 'update_note' => true,
      'upload_file' => _aiSupportedUploadTypes.contains(payload['type']),
      _ => false,
    };
  }
}
