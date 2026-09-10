import 'package:dio/dio.dart';

/// Kicks off the backend's chunk/embed pipeline for an item right after it
/// syncs to Supabase (see `SyncService`). A note or PDF is fully usable —
/// readable, editable, listed — before AI processing ever runs, so failing
/// to *reach* the backend here never blocks the user (requirements doc,
/// rule 15).
///
/// Not silent, though: this reports whether the request actually reached
/// the backend, so `SyncService` can queue a persistent `trigger_ai` retry
/// (survives an app restart, same as any other queued op) instead of the
/// attempt just vanishing — the old fire-and-forget version left an item
/// stuck in `pending` forever with no record anything had gone wrong.
class AiProcessingTrigger {
  AiProcessingTrigger(this._dio);

  final Dio? _dio;

  /// `true` if the backend accepted the request (or there was nothing to
  /// do — `BACKEND_URL` isn't configured, which isn't a failure to retry,
  /// it's a deployment that doesn't have AI processing at all); `false` if
  /// the request didn't reach the backend (network error, backend down, a
  /// non-2xx response).
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
