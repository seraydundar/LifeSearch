import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/failure.dart';
import 'export_payload.dart';

/// Builds a JSON export of everything the user has saved (requirements
/// doc, section 49-52: "Export") and writes it to a temp file for the
/// caller to hand off (e.g. via the OS share sheet — see
/// `ExportController`). Supabase-direct, like the rest of Settings/Items;
/// see `export_payload.dart` for the (independently testable) shape.
class ExportService {
  ExportService(this._client);

  final SupabaseClient _client;

  Future<File> exportUserDataAsJson() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw const AuthFailure('Oturum bulunamadı.');

    final itemRows =
        await _client.from('items').select().eq('user_id', userId).order('created_at');
    final itemIds = itemRows.map((row) => row['id'] as String).toList();

    final noteContentByItemId = <String, String>{};
    final tagsByItemId = <String, List<String>>{};

    if (itemIds.isNotEmpty) {
      final contentRows = await _client
          .from('item_contents')
          .select('item_id, raw_text')
          .inFilter('item_id', itemIds);
      for (final row in contentRows) {
        final text = row['raw_text'] as String?;
        if (text != null) noteContentByItemId[row['item_id'] as String] = text;
      }

      final tagRows = await _client
          .from('item_tags')
          .select('item_id, tags(name)')
          .inFilter('item_id', itemIds);
      for (final row in tagRows) {
        final itemId = row['item_id'] as String;
        final tagName = (row['tags'] as Map<String, dynamic>)['name'] as String;
        tagsByItemId.putIfAbsent(itemId, () => []).add(tagName);
      }
    }

    final payload = buildExportPayload(
      userId: userId,
      exportedAt: DateTime.now(),
      itemRows: itemRows,
      noteContentByItemId: noteContentByItemId,
      tagsByItemId: tagsByItemId,
    );

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/lifesearch-export-${DateTime.now().millisecondsSinceEpoch}.json');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(payload));
    return file;
  }
}
