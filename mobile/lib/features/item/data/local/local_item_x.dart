import 'package:drift/drift.dart' show Value;

import '../../../../core/database/app_database.dart';
import '../../domain/entities/item.dart';

/// `LocalItem` (the Drift row) → `Item` (the domain entity) — shared by
/// every repository that reads from the local cache (`OfflineItemRepository`
/// and, for the items inside a collection, `OfflineCollectionRepository`)
/// so the mapping only lives in one place.
extension LocalItemX on LocalItem {
  Item toDomainItem() => Item(
        id: id,
        type: ItemTypeX.fromDbValue(type),
        title: title,
        description: description,
        originalFilename: originalFilename,
        mimeType: mimeType,
        storagePath: storagePath,
        sourceUrl: sourceUrl,
        processingStatus: processingStatus,
        favorite: favorite,
        createdAt: createdAt,
        duplicateOfItemId: duplicateOfItemId,
        duplicateSimilarity: duplicateSimilarity,
        duplicateDismissed: duplicateDismissed,
        latitude: latitude,
        longitude: longitude,
        capturedAt: capturedAt,
        fileSizeBytes: fileSizeBytes,
        private: private,
      );
}

/// `Item` (the domain entity) → `LocalItemsCompanion` (the Drift row) —
/// the reverse of [LocalItemX.toDomainItem], for caching an item that
/// was just resolved some way *other* than the normal `SyncService`
/// archive pull (P2-09, docs/requirements-audit-2026-09-13.md: an item
/// not yet on this device, resolved on demand by
/// `OfflineItemRepository.findById`'s remote fallback). `noteContent`
/// isn't a field on `Item` itself (see `ItemRepository.fetchNoteContent`)
/// so it's a separate parameter here, same as `SyncService._pullRemote`
/// fetching it alongside each row.
extension ItemToLocalCompanionX on Item {
  LocalItemsCompanion toLocalItemsCompanion({
    required String userId,
    String syncStatus = 'synced',
    String? noteContent,
  }) {
    return LocalItemsCompanion.insert(
      id: id,
      userId: userId,
      type: type.dbValue,
      title: Value(title),
      description: Value(description),
      originalFilename: Value(originalFilename),
      mimeType: Value(mimeType),
      storagePath: Value(storagePath),
      sourceUrl: Value(sourceUrl),
      processingStatus: Value(processingStatus),
      favorite: Value(favorite),
      createdAt: createdAt,
      noteContent: Value(noteContent),
      duplicateOfItemId: Value(duplicateOfItemId),
      duplicateSimilarity: Value(duplicateSimilarity),
      duplicateDismissed: Value(duplicateDismissed),
      latitude: Value(latitude),
      longitude: Value(longitude),
      capturedAt: Value(capturedAt),
      fileSizeBytes: Value(fileSizeBytes),
      private: Value(private),
      syncStatus: Value(syncStatus),
    );
  }
}
