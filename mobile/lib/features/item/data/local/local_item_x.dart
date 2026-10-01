import 'package:drift/drift.dart' show Value;

import '../../../../core/database/app_database.dart';
import '../../domain/entities/item.dart';

/// `LocalItem` (Drift row) → `Item` (domain entity), shared by every
/// repository that reads the local cache.
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

/// Reverse of [LocalItemX.toDomainItem], for caching an item resolved
/// on demand outside the normal sync pull. `noteContent` isn't a field
/// on `Item`, so it's passed separately.
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
