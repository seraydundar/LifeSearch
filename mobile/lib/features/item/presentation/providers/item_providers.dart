import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_provider.dart';
import '../../../../core/network/api_client_provider.dart';
import '../../../../core/network/supabase_client_provider.dart';
import '../../../../core/sync/sync_providers.dart';
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
  return OfflineItemRepository(
    local: ref.watch(itemLocalDataSourceProvider),
    remote: ref.watch(remoteItemDataSourceProvider),
    queue: ref.watch(syncQueueDataSourceProvider),
    syncService: ref.watch(syncServiceProvider),
  );
});

/// Whether private items should currently be shown (Faz 11, madde 2 —
/// see docs/roadmap.md) — starts `false` every time the app is opened,
/// same amnesia as `appLockUnlockedProvider`, and flips back to `false`
/// whenever the app is backgrounded (see `AppLockGate`'s lifecycle
/// observer) — a private item re-hides itself even if the user never
/// turned on the whole-app lock. Only a successful `AppLockService.
/// authenticate()` (see `LibraryScreen`'s reveal button) sets this true.
final privateItemsRevealedProvider = StateProvider<bool>((ref) => false);

/// The repository's raw item stream, `private` items included — used
/// only where something needs to know which ids are private
/// (`SearchController`'s result filtering, via `.future`, so it awaits
/// the first real emission instead of reading a possibly-still-`loading`
/// cached value — a plain `.valueOrNull` here raced the very first
/// search of a session and let a private item's result through) without
/// ever *displaying* them. Every screen-facing list goes through
/// [itemsProvider] instead. Not private (no leading `_`) — search_providers.dart
/// awaits it directly.
final allItemsIncludingPrivateProvider = StreamProvider<List<Item>>((ref) {
  return ref.watch(itemRepositoryProvider).watchItems();
});

/// Local-first item list for the signed-in user — reads the Drift cache,
/// which `SyncService` keeps reconciled with Supabase. Home/Library both
/// watch this directly and it works fully offline. Hides `private` items
/// unless [privateItemsRevealedProvider] is true — the one place that
/// filter has to live for both screens to get it "for free".
final itemsProvider = StreamProvider<List<Item>>((ref) {
  final revealed = ref.watch(privateItemsRevealedProvider);
  return ref.watch(itemRepositoryProvider).watchItems().map(
        (items) => revealed ? items : items.where((i) => !i.private).toList(),
      );
});


/// Number of local changes still waiting to reach the server — shown in
/// Settings (requirements doc, section 49: "Sync"). Scoped to the
/// signed-in user (`SyncQueueEntries.userId`) — otherwise this would
/// count every account's pending writes on a shared device, not just
/// the one currently signed in.
final pendingSyncCountProvider = StreamProvider<int>((ref) {
  // Guarded the same way SyncService._currentUserIdOrNull() is: harmless
  // in the real app (main() always initializes Supabase first), but a
  // widget test that never touches Supabase shouldn't need to know this
  // provider reads it.
  String? userId;
  try {
    userId = ref.watch(supabaseClientProvider).auth.currentUser?.id;
  } catch (_) {
    userId = null;
  }
  if (userId == null) return Stream.value(0);
  return ref.watch(syncQueueDataSourceProvider).watchPendingCount(userId);
});

/// AI-generated tags for an item (requirements doc, section 8-12) — item
/// detail/note editor show these; empty while processing hasn't reached
/// the tagging step yet, or if it produced none.
final itemTagsProvider = FutureProvider.autoDispose.family<List<String>, String>((ref, itemId) {
  return ref.watch(itemRepositoryProvider).fetchTags(itemId);
});

/// AI-extracted named entities for an item (requirements doc, section
/// 44-48) — same lifecycle as `itemTagsProvider`.
final itemEntitiesProvider =
    FutureProvider.autoDispose.family<List<ExtractedEntity>, String>((ref, itemId) {
  return ref.watch(itemRepositoryProvider).fetchEntities(itemId);
});

/// Single item by id, local-cache only — used by `ItemByIdLoader` when a
/// route reaches `/item/:id` (or `/item/:id/note`) without the `Item`
/// object it normally gets handed via `state.extra` (see that widget's
/// docstring for when that happens).
final itemByIdProvider = FutureProvider.autoDispose.family<Item?, String>((ref, itemId) {
  return ref.watch(itemRepositoryProvider).findById(itemId);
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

  Future<bool> addLink(String url) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(itemRepositoryProvider).createUrlItem(url: url));
    return !state.hasError;
  }
}
