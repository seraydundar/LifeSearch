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
    String? extractedText,
    DateTime? createdAt,
    bool private = false,
  }) {
    return db.into(db.localItems).insert(LocalItemsCompanion.insert(
          id: id,
          userId: userId,
          type: type.dbValue,
          title: Value(title),
          description: Value(description),
          noteContent: Value(noteContent),
          sourceUrl: Value(sourceUrl),
          extractedText: Value(extractedText),
          createdAt: createdAt ?? DateTime(2026, 1, 1),
          private: Value(private),
        ));
  }

  Future<void> insertTag(String itemId, String name) {
    return db.into(db.localTags).insert(LocalTagsCompanion.insert(itemId: itemId, name: name));
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

  // P1-02 (docs/requirements-audit-2026-09-13.md): the offline keyword
  // fallback used to have no notion of `private` at all — it relied
  // entirely on `_hidePrivateResults`' cross-check downstream to catch a
  // private item, same as the remote RPCs before
  // 0017_search_excludes_private.sql. Excluding it here too is defense
  // in depth, matching that SQL fix's `include_private` contract.
  test('excludes a private item by default', () async {
    await insertItem(id: 'a', noteContent: 'Docker notes', private: true);

    final results = await dataSource.search('user-1', 'docker');

    expect(results, isEmpty);
  });

  test('includes a private item once includePrivate is true', () async {
    await insertItem(id: 'a', noteContent: 'Docker notes', private: true);

    final results = await dataSource.search('user-1', 'docker', includePrivate: true);

    expect(results.map((r) => r.itemId), ['a']);
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
    // "docker" needs to be its own word (space-delimited) here — TF-IDF
    // ranking (Faz 11, madde 6b) matches whole tokens, not "docker" as
    // a bare substring glued inside a longer run of letters the way the
    // old plain-substring search did (arguably a correctness fix on its
    // own: "xxxdockeryyy" isn't really a match for "docker").
    final longText = '${'lorem ' * 40}docker${' ipsum' * 40}';
    await insertItem(id: 'a', noteContent: longText);

    final results = await dataSource.search('user-1', 'docker');

    final snippet = results.single.snippet;
    expect(snippet.length, lessThan(longText.length));
    expect(snippet, contains('docker'));
    expect(snippet, startsWith('…'));
    expect(snippet, endsWith('…'));
  });

  // Faz 11, madde 6b (tam offline semantic search — see docs/roadmap.md):
  // TF-IDF ranking (tfidf_ranker.dart) replaced plain substring search.
  // These pin down exactly what that upgrade does over the old
  // behaviour — cross-field/order-independent multi-word matching and
  // relevance ranking — not just "still finds the same single-word hits".
  group('TF-IDF ranking (Faz 11, madde 6b)', () {
    test(
        'matches a multi-word query even when its words are in different fields, '
        'not one contiguous substring anywhere', () async {
      await insertItem(id: 'a', title: 'Kahve alışverişi', noteContent: 'Köşedeki dükkanı ziyaret et');
      await insertItem(id: 'b', title: 'Tamamen ilgisiz', noteContent: 'bir not');

      final results = await dataSource.search('user-1', 'kahve dükkanı');

      expect(results.map((r) => r.itemId), ['a']);
      // No field contains "kahve dükkanı" as one substring, so the
      // snippet falls back to an excerpt around whichever query word it
      // does find literally, instead of coming back empty.
      expect(results.single.snippet, isNotEmpty);
    });

    test('ranks the item containing more of the query terms above one containing fewer',
        () async {
      await insertItem(id: 'partial', noteContent: 'docker notes');
      await insertItem(
        id: 'full',
        noteContent: 'docker container image tutorial: building a docker image from a container',
      );

      final results = await dataSource.search('user-1', 'docker container image');

      expect(results.first.itemId, 'full');
    });

    test('a shared word gets a non-zero similarity, unlike the old fixed 0', () async {
      await insertItem(id: 'a', noteContent: 'Docker notes');

      final results = await dataSource.search('user-1', 'docker');

      expect(results.single.similarity, greaterThan(0));
    });
  });

  group('P2-07 (docs/requirements-audit-2026-09-13.md) — tags and extractedText', () {
    test('matches a query that only appears in extractedText (OCR/PDF/transcript text)',
        () async {
      await insertItem(
        id: 'a',
        title: 'Fotoğraf',
        extractedText: 'Bu görselde bir Docker container diyagramı var.',
      );

      final results = await dataSource.search('user-1', 'docker container');

      expect(results.map((r) => r.itemId), ['a']);
    });

    test('the snippet excerpts extractedText when that\'s where the match actually is',
        () async {
      await insertItem(id: 'a', title: 'Taranmış sayfa', extractedText: 'Sözleşme madde 5: fesih koşulları.');

      final results = await dataSource.search('user-1', 'fesih');

      expect(results.single.snippet, contains('fesih koşulları'));
    });

    test('matches a query that only appears in a tag', () async {
      await insertItem(id: 'a', title: 'Untitled note');
      await insertTag('a', 'flutter');
      await insertItem(id: 'b', title: 'Alakasız');

      final results = await dataSource.search('user-1', 'flutter');

      expect(results.map((r) => r.itemId), ['a']);
    });

    test('a multi-word query matches when one word is a tag and the other is in the body',
        () async {
      await insertItem(id: 'a', noteContent: 'state management üzerine notlar');
      await insertTag('a', 'riverpod');

      final results = await dataSource.search('user-1', 'riverpod state management');

      expect(results.map((r) => r.itemId), ['a']);
    });

    test('a stale item\'s tags in LocalTags never leak into another item\'s ranking',
        () async {
      await insertItem(id: 'a', title: 'A');
      await insertItem(id: 'b', title: 'B');
      await insertTag('a', 'docker');

      final results = await dataSource.search('user-1', 'docker');

      expect(results.map((r) => r.itemId), ['a']);
    });
  });
}
