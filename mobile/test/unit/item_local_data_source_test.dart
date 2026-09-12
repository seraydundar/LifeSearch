import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesearch/core/database/app_database.dart';
import 'package:lifesearch/features/item/data/local/item_local_data_source.dart';
import 'package:lifesearch/features/item/domain/entities/item.dart';

void main() {
  late AppDatabase db;
  late ItemLocalDataSource dataSource;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dataSource = ItemLocalDataSource(db);
  });

  tearDown(() => db.close());

  Future<void> insertItem({required String id, required String userId}) {
    return db.into(db.localItems).insert(LocalItemsCompanion.insert(
          id: id,
          userId: userId,
          type: ItemType.note.dbValue,
          title: Value('$userId\'s note'),
          noteContent: const Value('secret body'),
          createdAt: DateTime(2026, 1, 1),
        ));
  }

  group('findById (Faz 12, madde 3 — see docs/roadmap.md)', () {
    test('returns the item when it belongs to the given user', () async {
      await insertItem(id: 'item-1', userId: 'user-a');

      final result = await dataSource.findById('user-a', 'item-1');

      expect(result?.id, 'item-1');
      expect(result?.noteContent, 'secret body');
    });

    test(
        "does not return another account's cached item, even though it's still on "
        'this device (a real, previously-unfixed scenario — an item stays cached '
        'locally after sign-out, see Faz 10a\'s own documented limitation)', () async {
      await insertItem(id: 'a-item', userId: 'user-a');

      final asB = await dataSource.findById('user-b', 'a-item');

      expect(asB, isNull);
    });

    test('a nonexistent id returns null regardless of user', () async {
      final result = await dataSource.findById('user-a', 'does-not-exist');

      expect(result, isNull);
    });
  });
}
