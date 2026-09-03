import 'package:dio/dio.dart';

/// Kicks off the backend's chunk/embed pipeline for an item right after it
/// syncs to Supabase (see `SyncService`). Best-effort on purpose: a note
/// or PDF is fully usable — readable, editable, listed — before AI
/// processing ever runs, so a failure here never blocks the user
/// (requirements doc, rule 15).
class AiProcessingTrigger {
  AiProcessingTrigger(this._dio);

  final Dio? _dio;

  Future<void> triggerProcessing(String itemId) async {
    final dio = _dio;
    if (dio == null) return; // BACKEND_URL not configured — nothing to do
    try {
      await dio.post('/ai/process-item', data: {'item_id': itemId});
    } catch (_) {
      // Swallowed: the item just stays in 'pending' until the next
      // successful trigger. No user-facing error — there's nothing for
      // the user to act on right now.
    }
  }
}
