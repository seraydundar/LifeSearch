import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/network/paginated_fetch.dart';
import 'export_payload.dart';

/// Returns a `String`, not a `dart:io` `File`, so it works the same on web, where `path_provider` has no real filesystem.
class ExportService {
  ExportService(this._client);

  final SupabaseClient _client;

  Future<String> exportUserDataAsJson() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw const AuthFailure('Oturum bulunamadı.');

    // Paginated: a plain .select() silently truncates past PostgREST's row cap instead of erroring.
    final itemRows = await fetchAllPages((from, to) {
      return _client
          .from('items')
          .select()
          .eq('user_id', userId)
          .order('created_at')
          .order('id')
          .range(from, to);
    });
    final itemIds = itemRows.map((row) => row['id'] as String).toList();

    final rawTextByItemId = <String, String>{};
    final ocrTextByItemId = <String, String>{};
    final aiDescriptionByItemId = <String, String>{};
    final summaryByItemId = <String, String>{};
    final languageByItemId = <String, String>{};
    final tagsByItemId = <String, List<String>>{};
    final entitiesByItemId = <String, List<Map<String, String>>>{};

    if (itemIds.isNotEmpty) {
      // All item_contents columns — the previous export dropped ocr_text/ai_description/summary/language.
      final contentRows = await fetchAllPages((from, to) {
        return _client
            .from('item_contents')
            .select('item_id, raw_text, ocr_text, ai_description, summary, language')
            .inFilter('item_id', itemIds)
            .order('item_id')
            .range(from, to);
      });
      for (final row in contentRows) {
        final id = row['item_id'] as String;
        final rawText = row['raw_text'] as String?;
        final ocrText = row['ocr_text'] as String?;
        final aiDescription = row['ai_description'] as String?;
        final summary = row['summary'] as String?;
        final language = row['language'] as String?;
        if (rawText != null) rawTextByItemId[id] = rawText;
        if (ocrText != null) ocrTextByItemId[id] = ocrText;
        if (aiDescription != null) aiDescriptionByItemId[id] = aiDescription;
        if (summary != null) summaryByItemId[id] = summary;
        if (language != null) languageByItemId[id] = language;
      }

      final tagRows = await fetchAllPages((from, to) {
        return _client
            .from('item_tags')
            .select('item_id, tags(name)')
            .inFilter('item_id', itemIds)
            .order('item_id')
            .range(from, to);
      });
      for (final row in tagRows) {
        final itemId = row['item_id'] as String;
        final tagName = (row['tags'] as Map<String, dynamic>)['name'] as String;
        tagsByItemId.putIfAbsent(itemId, () => []).add(tagName);
      }

      // Same join-through-junction-table shape as tags.
      final entityRows = await fetchAllPages((from, to) {
        return _client
            .from('item_entities')
            .select('item_id, entities(name, type)')
            .inFilter('item_id', itemIds)
            .order('item_id')
            .range(from, to);
      });
      for (final row in entityRows) {
        final itemId = row['item_id'] as String;
        final entity = row['entities'] as Map<String, dynamic>;
        entitiesByItemId.putIfAbsent(itemId, () => []).add({
          'name': entity['name'] as String,
          'type': entity['type'] as String,
        });
      }
    }

    // Kept separate from RemoteCollectionDataSource since it lives in a different feature module.
    final collectionRows = await fetchAllPages((from, to) {
      return _client
          .from('collections')
          .select()
          .eq('user_id', userId)
          .order('created_at')
          .order('id')
          .range(from, to);
    });
    final collectionIds = collectionRows.map((row) => row['id'] as String).toList();

    final itemIdsByCollectionId = <String, List<String>>{};
    if (collectionIds.isNotEmpty) {
      final membershipRows = await fetchAllPages((from, to) {
        return _client
            .from('collection_items')
            .select('collection_id, item_id')
            .inFilter('collection_id', collectionIds)
            .order('collection_id')
            .order('item_id')
            .range(from, to);
      });
      for (final row in membershipRows) {
        final collectionId = row['collection_id'] as String;
        itemIdsByCollectionId.putIfAbsent(collectionId, () => []).add(row['item_id'] as String);
      }
    }

    final payload = buildExportPayload(
      userId: userId,
      exportedAt: DateTime.now(),
      itemRows: itemRows,
      rawTextByItemId: rawTextByItemId,
      ocrTextByItemId: ocrTextByItemId,
      aiDescriptionByItemId: aiDescriptionByItemId,
      summaryByItemId: summaryByItemId,
      languageByItemId: languageByItemId,
      tagsByItemId: tagsByItemId,
      entitiesByItemId: entitiesByItemId,
      collectionRows: collectionRows,
      itemIdsByCollectionId: itemIdsByCollectionId,
    );

    return const JsonEncoder.withIndent('  ').convert(payload);
  }
}
