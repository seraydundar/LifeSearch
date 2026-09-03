import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_provider.dart';
import '../../../../core/network/connectivity_provider.dart';
import '../../../../core/network/supabase_client_provider.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/local/item_local_data_source.dart';
import '../../data/local/sync_queue_data_source.dart';
import '../../data/remote/remote_item_data_source.dart';
import '../../data/repositories/offline_item_repository.dart';
import '../../data/sync/sync_service.dart';
import '../../domain/entities/item.dart';
import '../../domain/repositories/item_repository.dart';

final remoteItemDataSourceProvider = Provider<RemoteItemDataSource>((ref) {
  return RemoteItemDataSource(ref.watch(supabaseClientProvider));
});

final itemLocalDataSourceProvider = Provider<ItemLocalDataSource>((ref) {
  return ItemLocalDataSource(ref.watch(appDatabaseProvider));
});

final syncQueueDataSourceProvider = Provider<SyncQueueDataSource>((ref) {
  return SyncQueueDataSource(ref.watch(appDatabaseProvider));
});

/// Reconciles local cache ↔ Supabase. Kicked off whenever connectivity
/// returns or the user signs in; `itemRepositoryProvider` also nudges it
/// after every local write (see `SyncService.syncSoon`).
final syncServiceProvider = Provider<SyncService>((ref) {
  final service = SyncService(
    local: ref.watch(itemLocalDataSourceProvider),
    remote: ref.watch(remoteItemDataSourceProvider),
    queue: ref.watch(syncQueueDataSourceProvider),
  );

  final onlineSub = ref.listen(isOnlineProvider, (previous, next) {
    if (next.valueOrNull == true) service.syncSoon();
  });
  final authSub = ref.listen(authStateChangesProvider, (previous, next) {
    if (next.valueOrNull != null) service.syncSoon();
  });
  ref.onDispose(() {
    onlineSub.close();
    authSub.close();
  });

  service.syncSoon();
  return service;
});

final itemRepositoryProvider = Provider<ItemRepository>((ref) {
  return OfflineItemRepository(
    local: ref.watch(itemLocalDataSourceProvider),
    remote: ref.watch(remoteItemDataSourceProvider),
    queue: ref.watch(syncQueueDataSourceProvider),
    syncService: ref.watch(syncServiceProvider),
  );
});

/// Local-first item list for the signed-in user — reads the Drift cache,
/// which `SyncService` keeps reconciled with Supabase. Home/Library both
/// watch this directly and it works fully offline.
final itemsProvider = StreamProvider<List<Item>>((ref) {
  return ref.watch(itemRepositoryProvider).watchItems();
});

/// Number of local changes still waiting to reach the server — shown in
/// Settings (requirements doc, section 49: "Sync").
final pendingSyncCountProvider = StreamProvider<int>((ref) {
  return ref.watch(syncQueueDataSourceProvider).watchPendingCount();
});

final noteEditorControllerProvider =
    AsyncNotifierProvider<NoteEditorController, void>(NoteEditorController.new);

/// Owns save-in-progress / error state for the note editor screen.
class NoteEditorController extends AsyncNotifier<void> {
  @override
  void build() {}

  /// Returns the created/updated item, or `null` if saving failed (the
  /// error is available via this provider's `AsyncError` state).
  Future<Item?> save({
    required String? itemId,
    required String title,
    required String content,
  }) async {
    state = const AsyncLoading();
    Item? saved;
    state = await AsyncValue.guard(() async {
      final repo = ref.read(itemRepositoryProvider);
      if (itemId == null) {
        saved = await repo.createNote(title: title, content: content);
      } else {
        await repo.updateNote(itemId: itemId, title: title, content: content);
      }
    });
    return state.hasError ? null : saved;
  }
}

final captureControllerProvider =
    AsyncNotifierProvider<CaptureController, void>(CaptureController.new);

/// Owns upload-in-progress / error state for the "add content" flow.
class CaptureController extends AsyncNotifier<void> {
  @override
  void build() {}

  Future<bool> uploadFile({
    required String localFilePath,
    required String originalFilename,
    required String mimeType,
    required ItemType type,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(itemRepositoryProvider).uploadFile(
          localFilePath: localFilePath,
          originalFilename: originalFilename,
          mimeType: mimeType,
          type: type,
        ));
    return !state.hasError;
  }
}
