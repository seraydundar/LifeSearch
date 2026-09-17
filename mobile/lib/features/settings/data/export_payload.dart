/// Pure data-shaping for "Export my data" (requirements doc, section
/// 49-52) — kept separate from the Supabase I/O in `ExportService` so the
/// shape itself is unit-testable without a real client.
///
/// Only metadata and text content are included, never the binary files
/// themselves (photos/PDFs/audio) — downloading and zipping every file is
/// out of scope for a first cut, and the export says so explicitly rather
/// than silently omitting them.
///
/// `export_version: 2` (P2-08, docs/requirements-audit-2026-09-13.md):
/// v1 only carried a note's own body (misleadingly named `note_content`
/// even though it came from the same `item_contents.raw_text` every
/// content type writes to — see `processing_pipeline.py`), tags, and no
/// `private` flag or collection membership at all. v2 makes the scope an
/// explicit contract: every `item_contents` field, entities, `private`,
/// and which collections an item belongs to. There's no reader of a v1
/// export to migrate — it's a one-way share-and-done JSON blob, not a
/// format anything re-imports — so this is a clean rename rather than an
/// additive, backwards-compatible change.
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
