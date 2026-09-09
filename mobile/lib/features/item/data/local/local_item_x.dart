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
      );
}
