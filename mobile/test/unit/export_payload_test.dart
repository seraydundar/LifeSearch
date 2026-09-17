import 'package:flutter_test/flutter_test.dart';
import 'package:lifesearch/features/settings/data/export_payload.dart';

void main() {
  Map<String, dynamic> baseItemRow({
    String id = 'item-1',
    String type = 'note',
    String? title = 'Docker Notes',
    bool favorite = true,
    bool? private,
  }) {
    final row = {
      'id': id,
      'type': type,
      'title': title,
      'description': null,
      'original_filename': null,
      'source_url': null,
      'favorite': favorite,
      'created_at': '2026-01-01T00:00:00Z',
    };
    // Left out of the map entirely (rather than passed as null) when
    // unset, to also exercise buildExportPayload's fallback for a row
    // that never had the column selected at all — not just one where it
    // came back null.
    if (private != null) row['private'] = private;
    return row;
  }

  test('shapes each item row with its item_contents fields, tags and entities joined in', () {
    final payload = buildExportPayload(
      userId: 'user-1',
      exportedAt: DateTime(2026, 1, 1),
      itemRows: [baseItemRow()],
      rawTextByItemId: {'item-1': 'Docker container ile image arasındaki fark.'},
      ocrTextByItemId: {'item-1': 'taranmış metin'},
      aiDescriptionByItemId: {'item-1': 'bir diyagram'},
      summaryByItemId: {'item-1': 'kısa özet'},
      languageByItemId: {'item-1': 'tr'},
      tagsByItemId: {
        'item-1': ['docker', 'devops'],
      },
      entitiesByItemId: {
        'item-1': [
          {'name': 'Docker Inc.', 'type': 'organization'},
        ],
      },
      collectionRows: const [],
      itemIdsByCollectionId: const {},
    );

    final item = (payload['items'] as List).single as Map<String, dynamic>;
    expect(item['id'], 'item-1');
    expect(item['raw_text'], 'Docker container ile image arasındaki fark.');
    expect(item['ocr_text'], 'taranmış metin');
    expect(item['ai_description'], 'bir diyagram');
    expect(item['summary'], 'kısa özet');
    expect(item['language'], 'tr');
    expect(item['tags'], ['docker', 'devops']);
    expect(item['entities'], [
      {'name': 'Docker Inc.', 'type': 'organization'},
    ]);
    expect(item['favorite'], true);
  });

  // P2-08 (docs/requirements-audit-2026-09-13.md): v1 dropped the
  // `private` flag entirely — an exported archive couldn't tell a
  // private item apart from a regular one.
  test('carries the private flag through, defaulting to false when absent', () {
    final payload = buildExportPayload(
      userId: 'user-1',
      exportedAt: DateTime(2026, 1, 1),
      itemRows: [baseItemRow(id: 'a', private: true), baseItemRow(id: 'b')],
      rawTextByItemId: const {},
      ocrTextByItemId: const {},
      aiDescriptionByItemId: const {},
      summaryByItemId: const {},
      languageByItemId: const {},
      tagsByItemId: const {},
      entitiesByItemId: const {},
      collectionRows: const [],
      itemIdsByCollectionId: const {},
    );

    final items = (payload['items'] as List).cast<Map<String, dynamic>>();
    expect(items.firstWhere((i) => i['id'] == 'a')['private'], true);
    expect(items.firstWhere((i) => i['id'] == 'b')['private'], false);
  });

  // P2-08: collections/membership were missing from the export entirely.
  test('includes collections with the ids of the items in each one', () {
    final payload = buildExportPayload(
      userId: 'user-1',
      exportedAt: DateTime(2026, 1, 1),
      itemRows: const [],
      rawTextByItemId: const {},
      ocrTextByItemId: const {},
      aiDescriptionByItemId: const {},
      summaryByItemId: const {},
      languageByItemId: const {},
      tagsByItemId: const {},
      entitiesByItemId: const {},
      collectionRows: [
        {
          'id': 'coll-1',
          'name': 'Docker stuff',
          'is_smart': false,
          'created_at': '2026-01-01T00:00:00Z',
        },
      ],
      itemIdsByCollectionId: {
        'coll-1': ['item-1', 'item-2'],
      },
    );

    expect(payload['collection_count'], 1);
    final collection = (payload['collections'] as List).single as Map<String, dynamic>;
    expect(collection['id'], 'coll-1');
    expect(collection['name'], 'Docker stuff');
    expect(collection['item_ids'], ['item-1', 'item-2']);
  });

  test('an item with none of the optional fields gets sensible defaults', () {
    final payload = buildExportPayload(
      userId: 'user-1',
      exportedAt: DateTime(2026, 1, 1),
      itemRows: [baseItemRow(id: 'item-2', type: 'pdf', title: 'Some PDF', favorite: false)],
      rawTextByItemId: const {},
      ocrTextByItemId: const {},
      aiDescriptionByItemId: const {},
      summaryByItemId: const {},
      languageByItemId: const {},
      tagsByItemId: const {},
      entitiesByItemId: const {},
      collectionRows: const [],
      itemIdsByCollectionId: const {},
    );

    final item = (payload['items'] as List).single as Map<String, dynamic>;
    expect(item['raw_text'], null);
    expect(item['ocr_text'], null);
    expect(item['tags'], isEmpty);
    expect(item['entities'], isEmpty);
    expect(item['private'], false);
  });

  test('carries top-level metadata: version, user, timestamp, counts', () {
    final payload = buildExportPayload(
      userId: 'user-1',
      exportedAt: DateTime(2026, 3, 15, 10, 30),
      itemRows: const [],
      rawTextByItemId: const {},
      ocrTextByItemId: const {},
      aiDescriptionByItemId: const {},
      summaryByItemId: const {},
      languageByItemId: const {},
      tagsByItemId: const {},
      entitiesByItemId: const {},
      collectionRows: const [],
      itemIdsByCollectionId: const {},
    );

    expect(payload['export_version'], 2);
    expect(payload['user_id'], 'user-1');
    expect(payload['item_count'], 0);
    expect(payload['collection_count'], 0);
    expect(payload['exported_at'], DateTime(2026, 3, 15, 10, 30).toIso8601String());
    expect(payload['items'], isEmpty);
    expect(payload['collections'], isEmpty);
  });

  test('is honest that binary files themselves are not included', () {
    final payload = buildExportPayload(
      userId: 'user-1',
      exportedAt: DateTime(2026, 1, 1),
      itemRows: const [],
      rawTextByItemId: const {},
      ocrTextByItemId: const {},
      aiDescriptionByItemId: const {},
      summaryByItemId: const {},
      languageByItemId: const {},
      tagsByItemId: const {},
      entitiesByItemId: const {},
      collectionRows: const [],
      itemIdsByCollectionId: const {},
    );

    expect(payload['note'], contains('dahil değildir'));
  });
}
