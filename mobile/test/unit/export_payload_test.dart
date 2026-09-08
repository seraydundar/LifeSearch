import 'package:flutter_test/flutter_test.dart';
import 'package:lifesearch/features/settings/data/export_payload.dart';

void main() {
  test('shapes each item row with its note content and tags joined in', () {
    final payload = buildExportPayload(
      userId: 'user-1',
      exportedAt: DateTime(2026, 1, 1),
      itemRows: [
        {
          'id': 'item-1',
          'type': 'note',
          'title': 'Docker Notes',
          'description': null,
          'original_filename': null,
          'source_url': null,
          'favorite': true,
          'created_at': '2026-01-01T00:00:00Z',
        },
      ],
      noteContentByItemId: {'item-1': 'Docker container ile image arasındaki fark.'},
      tagsByItemId: {
        'item-1': ['docker', 'devops'],
      },
    );

    final item = (payload['items'] as List).single as Map<String, dynamic>;
    expect(item['id'], 'item-1');
    expect(item['note_content'], 'Docker container ile image arasındaki fark.');
    expect(item['tags'], ['docker', 'devops']);
    expect(item['favorite'], true);
  });

  test('an item with no note content or tags gets sensible defaults', () {
    final payload = buildExportPayload(
      userId: 'user-1',
      exportedAt: DateTime(2026, 1, 1),
      itemRows: [
        {
          'id': 'item-2',
          'type': 'pdf',
          'title': 'Some PDF',
          'description': null,
          'original_filename': 'some.pdf',
          'source_url': null,
          'favorite': false,
          'created_at': '2026-01-01T00:00:00Z',
        },
      ],
      noteContentByItemId: const {},
      tagsByItemId: const {},
    );

    final item = (payload['items'] as List).single as Map<String, dynamic>;
    expect(item['note_content'], isNull);
    expect(item['tags'], isEmpty);
  });

  test('carries top-level metadata: version, user, timestamp, count', () {
    final payload = buildExportPayload(
      userId: 'user-1',
      exportedAt: DateTime(2026, 3, 15, 10, 30),
      itemRows: const [],
      noteContentByItemId: const {},
      tagsByItemId: const {},
    );

    expect(payload['export_version'], 1);
    expect(payload['user_id'], 'user-1');
    expect(payload['item_count'], 0);
    expect(payload['exported_at'], DateTime(2026, 3, 15, 10, 30).toIso8601String());
    expect(payload['items'], isEmpty);
  });

  test('is honest that binary files themselves are not included', () {
    final payload = buildExportPayload(
      userId: 'user-1',
      exportedAt: DateTime(2026, 1, 1),
      itemRows: const [],
      noteContentByItemId: const {},
      tagsByItemId: const {},
    );

    expect(payload['note'], contains('dahil değildir'));
  });
}
