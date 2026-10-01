/// Pure data-shaping (unit-testable without a real client); only metadata/text are included, never binary files — out of scope, and the export says so explicitly.
Map<String, dynamic> buildExportPayload({
  required String userId,
  required DateTime exportedAt,
  required List<Map<String, dynamic>> itemRows,
  required Map<String, String> rawTextByItemId,
  required Map<String, String> ocrTextByItemId,
  required Map<String, String> aiDescriptionByItemId,
  required Map<String, String> summaryByItemId,
  required Map<String, String> languageByItemId,
  required Map<String, List<String>> tagsByItemId,
  required Map<String, List<Map<String, String>>> entitiesByItemId,
  required List<Map<String, dynamic>> collectionRows,
  required Map<String, List<String>> itemIdsByCollectionId,
}) {
  final items = itemRows.map((row) {
    final id = row['id'] as String;
    return {
      'id': id,
      'type': row['type'],
      'title': row['title'],
      'description': row['description'],
      'original_filename': row['original_filename'],
      'source_url': row['source_url'],
      'favorite': row['favorite'],
      'private': row['private'] as bool? ?? false,
      'created_at': row['created_at'],
      'raw_text': rawTextByItemId[id],
      'ocr_text': ocrTextByItemId[id],
      'ai_description': aiDescriptionByItemId[id],
      'summary': summaryByItemId[id],
      'language': languageByItemId[id],
      'tags': tagsByItemId[id] ?? const <String>[],
      'entities': entitiesByItemId[id] ?? const <Map<String, String>>[],
    };
  }).toList();

  final collections = collectionRows.map((row) {
    final id = row['id'] as String;
    return {
      'id': id,
      'name': row['name'],
      'is_smart': row['is_smart'],
      'created_at': row['created_at'],
      'item_ids': itemIdsByCollectionId[id] ?? const <String>[],
    };
  }).toList();

  return {
    'export_version': 2,
    'exported_at': exportedAt.toIso8601String(),
    'user_id': userId,
    'item_count': items.length,
    'collection_count': collections.length,
    'note': "Bu dışa aktarım yalnızca metin/metadata içerir — fotoğraf, "
        'PDF ve ses dosyalarının kendisi dahil değildir.',
    'items': items,
    'collections': collections,
  };
}
