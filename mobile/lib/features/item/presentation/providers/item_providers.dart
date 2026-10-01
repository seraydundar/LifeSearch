import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_provider.dart';
import '../../../../core/network/api_client_provider.dart';
import '../../../../core/network/supabase_client_provider.dart';
import '../../../../core/sync/sync_providers.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/local/item_local_data_source.dart';
import '../../data/local/sync_queue_data_source.dart';
import '../../data/remote/ai_processing_trigger.dart';
import '../../data/remote/remote_item_data_source.dart';
import '../../data/repositories/offline_item_repository.dart';
import '../../domain/entities/extracted_entity.dart';
import '../../domain/entities/item.dart';
import '../../domain/repositories/item_repository.dart';

final remoteItemDataSourceProvider = Provider<RemoteItemDataSource>((ref) {
  return RemoteItemDataSource(ref.watch(supabaseClientProvider));
});

final aiProcessingTriggerProvider = Provider<AiProcessingTrigger>((ref) {
  return AiProcessingTrigger(ref.watch(apiClientProvider));
});

final itemLocalDataSourceProvider = Provider<ItemLocalDataSource>((ref) {
  return ItemLocalDataSource(ref.watch(appDatabaseProvider));
});

final syncQueueDataSourceProvider = Provider<SyncQueueDataSource>((ref) {
  return SyncQueueDataSource(ref.watch(appDatabaseProvider));
});

final itemRepositoryProvider = Provider<ItemRepository>((ref) {
  // Unused value, but watching it rebuilds this (and everything derived
  // from it) across an account switch.
  ref.watch(currentUserIdProvider);
  return OfflineItemRepository(
    local: ref.watch(itemLocalDataSourceProvider),
    remote: ref.watch(remoteItemDataSourceProvider),
    queue: ref.watch(syncQueueDataSourceProvider),
    syncService: ref.watch(syncServiceProvider),
  );
});

/// Starts `false` on every app open and resets to `false` whenever the
/// app is backgrounded (see `AppLockGate`), so a private item re-hides
/// itself even without the whole-app lock on.
final privateItemsRevealedProvider = StateProvider<bool>((ref) => false);

/// Raw item stream including `private` items, for filtering logic only
/// (e.g. `SearchController`, via `.future` to avoid a stale cached
/// `.valueOrNull` racing the first search of a session) — never for
/// display. Screens use [itemsProvider] instead.
final allItemsIncludingPrivateProvider = StreamProvider<List<Item>>((ref) {
  return ref.watch(itemRepositoryProvider).watchItems();
});

/// Local-first item list for the signed-in user; hides `private` items
/// unless [privateItemsRevealedProvider] is true.
final itemsProvider = StreamProvider<List<Item>>((ref) {
  final revealed = ref.watch(privateItemsRevealedProvider);
  return ref.watch(itemRepositoryProvider).watchItems().map(
        (items) => revealed ? items : items.where((i) => !i.private).toList(),
      );
});

/// Scoped to the signed-in user so a shared device doesn't count every
/// account's pending writes.
final pendingSyncCountProvider = StreamProvider<int>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return Stream.value(0);
  return ref.watch(syncQueueDataSourceProvider).watchPendingCount(userId);
});

final itemTagsProvider = FutureProvider.autoDispose.family<List<String>, String>((ref, itemId) {
  return ref.watch(itemRepositoryProvider).fetchTags(itemId);
});

final itemEntitiesProvider =
    FutureProvider.autoDispose.family<List<ExtractedEntity>, String>((ref, itemId) {
  return ref.watch(itemRepositoryProvider).fetchEntities(itemId);
});

/// Local-cache-only lookup for `ItemByIdLoader`, when a route is reached
/// without the `Item` already in hand via `state.extra`.
final itemByIdProvider = FutureProvider.autoDispose.family<Item?, String>((ref, itemId) {
  return ref.watch(itemRepositoryProvider).findById(itemId);
});

/// Same as [itemByIdProvider] but live — re-emits on every local change
/// instead of a one-shot snapshot, so `ItemDetailScreen` reflects a
/// background sync completing while it's open. Derived from
/// [allItemsIncludingPrivateProvider], not [itemsProvider], so a private
/// item's own detail screen keeps showing it regardless of reveal state.
final watchItemByIdProvider = Provider.autoDispose.family<Item?, String>((ref, itemId) {
  final items = ref.watch(allItemsIncludingPrivateProvider).valueOrNull;
  if (items == null) return null;
  for (final item in items) {
    if (item.id == itemId) return item;
  }
  return null; // not synced to this device yet — same contract as findById()
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

  /// Same contract as [uploadFile], for web's bytes-based picker flow.
  Future<bool> uploadFileBytes({
    required Uint8List bytes,
    required String originalFilename,
    required String mimeType,
    required ItemType type,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(itemRepositoryProvider).uploadFileBytes(
          bytes: bytes,
          originalFilename: originalFilename,
          mimeType: mimeType,
          type: type,
        ));
    return !state.hasError;
  }

  Future<bool> addLink(String url) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(itemRepositoryProvider).createUrlItem(url: url));
    return !state.hasError;
  }
}
