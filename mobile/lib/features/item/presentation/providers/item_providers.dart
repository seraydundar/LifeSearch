import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/supabase_client_provider.dart';
import '../../data/repositories/supabase_item_repository.dart';
import '../../domain/entities/item.dart';
import '../../domain/repositories/item_repository.dart';

final itemRepositoryProvider = Provider<ItemRepository>((ref) {
  return SupabaseItemRepository(ref.watch(supabaseClientProvider));
});

/// Realtime item list for the signed-in user. Home/Library both watch this
/// directly — no separate fetch-on-navigate step.
final itemsProvider = StreamProvider<List<Item>>((ref) {
  return ref.watch(itemRepositoryProvider).watchItems();
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
