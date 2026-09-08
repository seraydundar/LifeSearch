/// Pure data-shaping for "Export my data" (requirements doc, section
/// 49-52) — kept separate from the Supabase I/O in `ExportService` so the
/// shape itself is unit-testable without a real client.
///
/// Only metadata and text content are included, never the binary files
/// themselves (photos/PDFs/audio) — downloading and zipping every file is
/// out of scope for a first cut, and the export says so explicitly rather
/// than silently omitting them.
Map<String, dynamic> buildExportPayload({
  required String userId,
  required DateTime exportedAt,
  required List<Map<String, dynamic>> itemRows,
  required Map<String, String> noteContentByItemId,
  required Map<String, List<String>> tagsByItemId,
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
      'created_at': row['created_at'],
      'note_content': noteContentByItemId[id],
      'tags': tagsByItemId[id] ?? const <String>[],
    };
  }).toList();

  return {
    'export_version': 1,
    'exported_at': exportedAt.toIso8601String(),
    'user_id': userId,
    'item_count': items.length,
    'note': "Bu dışa aktarım yalnızca metin/metadata içerir — fotoğraf, "
        'PDF ve ses dosyalarının kendisi dahil değildir.',
    'items': items,
  };
}
