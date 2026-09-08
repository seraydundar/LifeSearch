import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesearch/core/database/app_database.dart';
import 'package:lifesearch/features/item/domain/entities/item.dart';
import 'package:lifesearch/features/search/data/local/local_search_data_source.dart';
import 'package:lifesearch/features/search/domain/entities/search_filters.dart';

void main() {
  late AppDatabase db;
  late LocalSearchDataSource dataSource;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dataSource = LocalSearchDataSource(db);
  });

  tearDown(() => db.close());

  Future<void> insertItem({
    required String id,
    String userId = 'user-1',
    ItemType type = ItemType.note,
    String? title,
    String? description,
    String? noteContent,
    String? sourceUrl,
    DateTime? createdAt,
  }) {
    return db.into(db.localItems).insert(LocalItemsCompanion.insert(
          id: id,
          userId: userId,
          type: type.dbValue,
          title: Value(title),
          description: Value(description),
          noteContent: Value(noteContent),
          sourceUrl: Value(sourceUrl),
          createdAt: createdAt ?? DateTime(2026, 1, 1),
        ));
  }

  test('a blank query never matches anything', () async {
    await insertItem(id: 'a', noteContent: 'Docker notes');

    final results = await dataSource.search('user-1', '   ');

    expect(results, isEmpty);
  });

  test('matches inside a note\'s body, case-insensitively', () async {
    await insertItem(id: 'a', title: 'Untitled', noteContent: 'Docker container ile image arasındaki fark.');

    final results = await dataSource.search('user-1', 'DOCKER');

    expect(results, hasLength(1));
    expect(results.single.itemId, 'a');
    expect(results.single.snippet, contains('Docker container'));
  });

  test('falls back to title when nothing else matches', () async {
    await insertItem(id: 'a', title: 'Docker Cheatsheet');

    final results = await dataSource.search('user-1', 'docker');

    expect(results.single.itemTitle, 'Docker Cheatsheet');
  });

  test('does not match a different user\'s items', () async {
    await insertItem(id: 'a', userId: 'someone-else', noteContent: 'Docker notes');

    final results = await dataSource.search('user-1', 'docker');

    expect(results, isEmpty);
  });

  test('a null userId (nobody signed in) never matches anything', () async {
    await insertItem(id: 'a', noteContent: 'Docker notes');

    final results = await dataSource.search(null, 'docker');

    expect(results, isEmpty);
  });

  test('respects a type filter', () async {
    await insertItem(id: 'a', type: ItemType.note, noteContent: 'Docker notes');
    await insertItem(id: 'b', type: ItemType.pdf, title: 'Docker PDF');

    final results = await dataSource.search(
      'user-1',
      'docker',
      filters: const SearchFilters(types: {ItemType.pdf}),
    );

    expect(results.map((r) => r.itemId), ['b']);
  });

  test('respects a dateFrom filter', () async {
    await insertItem(id: 'old', noteContent: 'Docker notes', createdAt: DateTime(2020, 1, 1));
    await insertItem(id: 'new', noteContent: 'Docker notes', createdAt: DateTime(2026, 1, 1));

    final results = await dataSource.search(
      'user-1',
      'docker',
      filters: SearchFilters(dateFrom: DateTime(2025, 1, 1)),
    );

    expect(results.map((r) => r.itemId), ['new']);
  });

  test('excerpts long matches around the hit instead of returning the whole field', () async {
    final longText = '${'x' * 200}docker${'y' * 200}';
    await insertItem(id: 'a', noteContent: longText);

    final results = await dataSource.search('user-1', 'docker');

    final snippet = results.single.snippet;
    expect(snippet.length, lessThan(longText.length));
    expect(snippet, contains('docker'));
    expect(snippet, startsWith('…'));
    expect(snippet, endsWith('…'));
  });
}
