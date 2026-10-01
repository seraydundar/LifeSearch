import 'package:dio/dio.dart';

/// Kicks off the backend's chunk/embed pipeline after an item syncs.
/// Never blocks the user — a note/PDF is usable before processing runs.
/// Returns success so `SyncService` can queue a retry instead of silently
/// leaving an item stuck in `pending`.
class AiProcessingTrigger {
  AiProcessingTrigger(this._dio);

  final Dio? _dio;

  /// `false` only if the request failed to reach the backend; missing
  /// `BACKEND_URL` counts as success (nothing to do, not a failure).
  Future<bool> triggerProcessing(String itemId) async {
    final dio = _dio;
    if (dio == null) return true; // BACKEND_URL not configured — nothing to do
    try {
      await dio.post('/ai/process-item', data: {'item_id': itemId});
      return true;
    } catch (_) {
      return false;
    }
  }
}
