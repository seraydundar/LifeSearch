import 'dart:typed_data';

import '../entities/extracted_entity.dart';
import '../entities/item.dart';

/// Contract the presentation layer codes against. Deliberately takes plain
/// paths/bytes rather than `dart:io` types so the domain layer stays
/// platform-agnostic — only `features/item/data` knows about files or
/// Supabase Storage.
abstract interface class ItemRepository {
  Stream<List<Item>> watchItems();

  Future<String> fetchNoteContent(String itemId);

  /// AI-generated tags. Not cached locally — needs a connection to show.
  Future<List<String>> fetchTags(String itemId);

  /// One entry per (item, tag) across the whole archive, for Analytics'
  /// "most common tags". Same "needs a connection" contract as [fetchTags].
  Future<List<String>> fetchAllTagNames();

  /// AI-extracted named entities mentioned in an item's content. Same
  /// "needs a connection" contract as [fetchTags].
  Future<List<ExtractedEntity>> fetchEntities(String itemId);

  /// Local cache first, then a remote lookup for an id this device hasn't
  /// synced yet (caching the result). `null` only if both come up empty.
  Future<Item?> findById(String itemId);

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

  /// Same contract as [uploadFile], for a caller with only in-memory
  /// bytes (e.g. web's `file_picker`). Uploads immediately and doesn't
  /// queue a retry — there's no persistent local copy to replay later.
  Future<Item> uploadFileBytes({
    required Uint8List bytes,
    required String originalFilename,
    required String mimeType,
    required ItemType type,
  });

  Future<Item> createUrlItem({required String url});

  /// Short-lived signed URL for viewing/downloading a private-bucket file.
  Future<String> getSignedUrl(String storagePath);

  Future<void> setFavorite(String itemId, bool favorite);

  /// A private item is hidden from Home/Library/Search unless revealed
  /// for the session.
  Future<void> setPrivate(String itemId, bool private);

  /// Hides the duplicate banner for good; doesn't touch either item.
  Future<void> dismissDuplicate(String itemId);

  Future<void> deleteItem(Item item);

  /// Re-runs the AI pipeline for an item stuck `failed` or never
  /// triggered. Returns once the retry is queued locally, not once
  /// processing finishes.
  Future<void> retryProcessing(String itemId);
}
