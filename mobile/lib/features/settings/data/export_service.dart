import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/failure.dart';
import 'export_payload.dart';

/// Builds a JSON export of everything the user has saved (requirements
/// doc, section 49-52: "Export") as a plain string for the caller to
/// hand off (e.g. via the OS share sheet — see `ExportController`).
/// Supabase-direct, like the rest of Settings/Items; see
/// `export_payload.dart` for the (independently testable) shape.
///
/// Deliberately returns a `String`, not a `dart:io` `File` written to a
/// temp directory — that would need `path_provider`, which has no real
/// filesystem to work with on web (Faz 11, madde 6c, see
/// docs/roadmap.md). Sharing straight from bytes via `XFile.fromData`
/// (see `ExportController`) works identically on every platform, so
/// this isn't a "disabled on web" limitation, just a simpler design
/// that happens to also be portable.
class ExportService {
  ExportService(this._client);

  final SupabaseClient _client;

  Future<String> exportUserDataAsJson() async {
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

    return const JsonEncoder.withIndent('  ').convert(payload);
  }
}
