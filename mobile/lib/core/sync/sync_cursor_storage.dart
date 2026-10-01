import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the timestamp `SyncService` last pulled items up to, per user. Keyed by `userId` — a shared
/// cursor would make a freshly-signed-in second account's first sync wrongly "incremental", silently
/// skipping items that account hasn't synced yet.
class SyncCursorStorage {
  SyncCursorStorage({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secureStorage;

  String _key(String userId) => 'items_synced_since_$userId';

  /// `null` means never synced on this device — caller does a full pull instead of incremental.
  Future<DateTime?> read(String userId) async {
    final value = await _secureStorage.read(key: _key(userId));
    if (value == null) return null;
    return DateTime.tryParse(value);
  }

  Future<void> write(String userId, DateTime at) {
    return _secureStorage.write(key: _key(userId), value: at.toIso8601String());
  }
}
