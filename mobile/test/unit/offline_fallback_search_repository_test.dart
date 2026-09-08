import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesearch/core/database/app_database.dart';
import 'package:lifesearch/core/error/failure.dart';
import 'package:lifesearch/features/item/domain/entities/item.dart';
import 'package:lifesearch/features/search/data/local/local_search_data_source.dart';
import 'package:lifesearch/features/search/data/local/offline_fallback_search_repository.dart';

import '../fakes/fake_search_repository.dart';

void main() {
  late AppDatabase db;
  late LocalSearchDataSource local;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    local = LocalSearchDataSource(db);
  });

  tearDown(() => db.close());

  test('prefers the remote result when the remote call succeeds', () async {
    await db.into(db.localItems).insert(LocalItemsCompanion.insert(
          id: 'a',
          userId: 'user-1',
          type: ItemType.note.dbValue,
          noteContent: const Value('docker notes'),
          createdAt: DateTime(2026, 1, 1),
        ));
    final remote = FakeSearchRepository(resultsToReturn: [fakeSearchResult(itemId: 'remote-hit')]);
    final repo = OfflineFallbackSearchRepository(
      remote: remote,
      local: local,
      currentUserId: () => 'user-1',
    );

    final results = await repo.search('docker');

    expect(results.map((r) => r.itemId), ['remote-hit']);
  });

  test('falls back to local keyword matches when the remote call throws', () async {
    await db.into(db.localItems).insert(LocalItemsCompanion.insert(
          id: 'a',
          userId: 'user-1',
          type: ItemType.note.dbValue,
          noteContent: const Value('docker notes'),
          createdAt: DateTime(2026, 1, 1),
        ));
    final remote = FakeSearchRepository(
      errorToThrow: const UnexpectedFailure('Arama şu anda kullanılamıyor.'),
    );
    final repo = OfflineFallbackSearchRepository(
      remote: remote,
      local: local,
      currentUserId: () => 'user-1',
    );

    final results = await repo.search('docker');

    expect(results.map((r) => r.itemId), ['a']);
  });

  test('related() always goes to remote — no offline analog', () async {
    final remote = FakeSearchRepository(relatedToReturn: [fakeSearchResult(itemId: 'related-1')]);
    final repo = OfflineFallbackSearchRepository(
      remote: remote,
      local: local,
      currentUserId: () => 'user-1',
    );

    final results = await repo.related('item-1');

    expect(results.map((r) => r.itemId), ['related-1']);
  });
}
