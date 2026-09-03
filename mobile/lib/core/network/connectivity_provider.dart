import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the device currently has *some* network path (Wi-Fi or mobile).
/// This is what `SyncService` watches to know when to flush the offline
/// queue — it's a connectivity check, not proof Supabase itself is
/// reachable, so a sync attempt can still fail and gets retried.
final isOnlineProvider = StreamProvider<bool>((ref) {
  final connectivity = Connectivity();
  return connectivity.onConnectivityChanged.map(_hasConnection);
});

bool _hasConnection(List<ConnectivityResult> results) {
  return results.any((r) => r != ConnectivityResult.none);
}
