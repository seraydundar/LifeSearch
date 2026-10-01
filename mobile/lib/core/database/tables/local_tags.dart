import 'package:drift/drift.dart';

/// Local cache of the `item_tags`/`tags` join. Read-only (AI-generated server-side) — no `syncStatus`,
/// `SyncService._pullRemote` just replaces the whole cache each sync. No `userId`: scoping goes through
/// a join against `LocalItems` instead.
class LocalTags extends Table {
  TextColumn get itemId => text()();
  TextColumn get name => text()();

  @override
  Set<Column> get primaryKey => {itemId, name};
}
