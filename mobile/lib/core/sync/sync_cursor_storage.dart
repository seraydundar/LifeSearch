import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the timestamp `SyncService` last successfully pulled items up
/// to, per user (P3, docs/requirements-audit-2026-09-13.md, "Ölçek/ölçüm")
/// — `flutter_secure_storage`, same tradeoff as `ThemePreferenceService`/
/// `AppLockService`: not itself sensitive, but already a dependency, and
/// Drift has no generic key-value settings table yet.
///
/// Keyed by `userId` rather than one global value: the local Drift cache
/// itself already holds multiple accounts' items side by side, scoped by
/// a `userId` column (see `ItemLocalDataSource.findById`) — a shared
/// cursor would make a freshly-signed-in second account's first sync
/// incorrectly "incremental" against the first account's cursor, silently
/// skipping everything that account's own items haven't changed since.
class SyncCursorStorage {
  SyncCursorStorage({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secureStorage;

  String _key(String userId) => 'items_synced_since_$userId';

  /// `null` means "never synced this account on this device" — the
  /// caller's cue to do a full pull instead of an incremental one.
  Future<DateTime?> read(String userId) async {
    final value = await _secureStorage.read(key: _key(userId));
    if (value == null) return null;
    return DateTime.tryParse(value);
  }

  Future<void> write(String userId, DateTime at) {
    return _secureStorage.write(key: _key(userId), value: at.toIso8601String());
  }
}
