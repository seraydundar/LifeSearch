import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesearch/core/database/app_database.dart';
import 'package:lifesearch/features/search/data/local/recent_searches_data_source.dart';

void main() {
  late AppDatabase db;
  late RecentSearchesDataSource source;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    source = RecentSearchesDataSource(db);
  });

  tearDown(() => db.close());

  test('one account never sees another account\'s search history', () async {
    // Search history had no userId at all before Faz 10a — every account
    // on a shared device read (and could clear) the same list.
    await source.record('user-1', 'docker compose');
    await source.record('user-2', 'gaming monitor');

    expect(await source.watchRecent('user-1').first, ['docker compose']);
    expect(await source.watchRecent('user-2').first, ['gaming monitor']);
  });

  test('recording the same query again moves it to the front, not a duplicate', () async {
    await source.record('user-1', 'docker');
    await source.record('user-1', 'flutter');
    await source.record('user-1', 'docker'); // re-searched

    final recent = await source.watchRecent('user-1').first;
    expect(recent, ['docker', 'flutter']); // newest first, no duplicate
  });

  test('clearing one account\'s history leaves another account\'s untouched', () async {
    await source.record('user-1', 'docker compose');
    await source.record('user-2', 'gaming monitor');

    await source.clear('user-1');

    expect(await source.watchRecent('user-1').first, isEmpty);
    expect(await source.watchRecent('user-2').first, ['gaming monitor']);
  });

  test('a blank query is never recorded', () async {
    await source.record('user-1', '   ');

    expect(await source.watchRecent('user-1').first, isEmpty);
  });
}
