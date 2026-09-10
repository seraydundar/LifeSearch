import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';

class SyncQueueDataSource {
  SyncQueueDataSource(this._db);

  final AppDatabase _db;

  Future<void> enqueue({
    required String userId,
    required String operationType,
    required String itemId,
    required Map<String, dynamic> payload,
  }) {
    return _db.into(_db.syncQueueEntries).insert(
          SyncQueueEntriesCompanion.insert(
            userId: Value(userId),
            operationType: operationType,
            itemId: itemId,
            payload: jsonEncode(payload),
          ),
        );
  }

  /// Only `userId`'s own queued writes — see `SyncQueueEntries.userId`'s
  /// docstring for why this matters on a shared device.
  Future<List<SyncQueueEntry>> pendingEntries(String userId) {
    return (_db.select(_db.syncQueueEntries)
          ..where((t) => t.userId.equals(userId))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  Stream<int> watchPendingCount(String userId) {
    final query = _db.selectOnly(_db.syncQueueEntries)
      ..addColumns([_db.syncQueueEntries.id.count()])
      ..where(_db.syncQueueEntries.userId.equals(userId));
    return query.map((row) => row.read(_db.syncQueueEntries.id.count()) ?? 0).watchSingle();
  }

  Future<void> remove(int id) {
    return (_db.delete(_db.syncQueueEntries)..where((t) => t.id.equals(id))).go();
  }

  /// Bumps the retry counter and records the error in one statement, so a
  /// failed sync attempt never races with itself.
  Future<void> recordFailure(int id, String error) {
    return _db.customStatement(
      'UPDATE sync_queue_entries SET retry_count = retry_count + 1, last_error = ? WHERE id = ?',
      [error, id],
    );
  }
}
