import 'dart:typed_data';

import '../entities/extracted_entity.dart';
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

  /// Tags attached to an item — AI-generated during processing (vision
  /// analysis for images, a text-completion call for everything else),
  /// see backend/app/services/tagging_service.py. Not cached locally yet,
  /// same as `getSignedUrl` — needs a connection to show.
  Future<List<String>> fetchTags(String itemId);

  /// Every tag occurrence across the whole archive, one entry per
  /// (item, tag) — the Analytics screen's "most common tags" (see
  /// docs/roadmap.md, Faz 11, madde 3). Same "not cached locally yet,
  /// needs a connection to show" contract as [fetchTags].
  Future<List<String>> fetchAllTagNames();

  /// AI-extracted named entities (people, places, organizations, dates)
  /// mentioned in an item's content, see
  /// backend/app/services/entity_extraction_service.py. Same "not cached
  /// locally yet, needs a connection to show" contract as `fetchTags`.
  Future<List<ExtractedEntity>> fetchEntities(String itemId);

  /// Single item by id — the local cache first, then (P2-09, docs/
  /// requirements-audit-2026-09-13.md) a remote lookup for an id this
  /// device hasn't synced yet, caching the result for next time. `null`
  /// only once both come up empty (or there's no connection to even try
  /// the remote fallback) — used for the duplicate-candidate banner on
  /// item detail (needs the *other* item's title/type without loading
  /// the whole list) and for resolving a route reached without the full
  /// `Item` already in hand (`ItemByIdLoader`).
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

  /// Same contract as [uploadFile], for a caller that only has the
  /// file's bytes in memory, not a real filesystem path (P3, docs/
  /// requirements-audit-2026-09-13.md, "Platformlar" — web's
  /// `file_picker` gives bytes, never a path). Uploads immediately and
  /// doesn't queue a retry on failure the way [uploadFile] does — there's
  /// no persistent local copy of these bytes to replay from later once
  /// the in-memory ones are gone (an app restart, on web, loses them
  /// completely) — the caller surfaces a failure directly instead.
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

  /// Item-level Privacy Mode (requirements doc; see docs/roadmap.md,
  /// Faz 11, madde 2) — a private item is hidden from Home/Library/Search
  /// (see `item_providers.dart`'s `itemsProvider`) unless private items
  /// have been revealed for the session.
  Future<void> setPrivate(String itemId, bool private);

  /// User says "this isn't actually a duplicate" (or "I know, ignore it") —
  /// hides the banner for good, doesn't touch either item's content.
  Future<void> dismissDuplicate(String itemId);

  Future<void> deleteItem(Item item);

  /// User-initiated re-run of the AI pipeline for an item stuck in
  /// `processingStatus == 'failed'` (the backend pipeline itself errored —
  /// e.g. a missing API key, a corrupt PDF) or one whose initial trigger
  /// never reached the backend at all. Fire-and-forget from the caller's
  /// perspective: this returns once the retry is queued locally, not once
  /// processing actually finishes — same contract as every other write
  /// here (requirements doc, section 38: the UI never blocks on the
  /// network).
  Future<void> retryProcessing(String itemId);
}
