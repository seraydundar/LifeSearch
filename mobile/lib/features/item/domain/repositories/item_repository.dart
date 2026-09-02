import '../entities/item.dart';

/// Contract the presentation layer codes against. Deliberately takes plain
/// paths/bytes rather than `dart:io` types so the domain layer stays
/// platform-agnostic — only `features/item/data` knows about files or
/// Supabase Storage.
abstract interface class ItemRepository {
  /// Realtime list of the current user's items, newest first. Backed by
  /// Supabase's realtime `stream()` — creating/deleting an item elsewhere
  /// updates this without an explicit refetch.
  Stream<List<Item>> watchItems();

  Future<String> fetchNoteContent(String itemId);

  Future<Item> createNote({required String title, required String content});

  Future<void> updateNote({
    required String itemId,
    required String title,
    required String content,
  });

  Future<Item> uploadFile({
    required String localFilePath,
    required String originalFilename,
    required String mimeType,
    required ItemType type,
  });

  /// Short-lived signed URL for viewing/downloading a private-bucket file.
  Future<String> getSignedUrl(String storagePath);

  Future<void> setFavorite(String itemId, bool favorite);

  Future<void> deleteItem(Item item);
}
