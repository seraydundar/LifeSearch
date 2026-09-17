import 'package:dio/dio.dart';

import '../../../core/error/failure.dart';

/// Calls the backend's `POST /ai/reprocess-stale-embeddings` (P3, docs/
/// requirements-audit-2026-09-13.md) — the on-request fix for chunks left
/// behind by an `AI_PROVIDER`/model switch (see `reembedding_service.py`).
/// User-triggered only, from Settings' "AI Status" row — never automatic,
/// since bulk re-embedding an entire archive is exactly the kind of
/// AI-cost spike that should never happen without being asked for.
class AiMaintenanceService {
  AiMaintenanceService(this._dio);

  final Dio? _dio;

  /// Returns how many items were found stale and scheduled for
  /// re-embedding — the actual work happens in the backend's background
  /// task after this call already returned (202 accepted), so this count
  /// is a snapshot, not a completion signal.
  Future<int> reprocessStaleEmbeddings() async {
    final dio = _dio;
    if (dio == null) {
      throw const UnexpectedFailure(
        'Şu anda kullanılamıyor. Backend bağlantısı ayarlanmamış.',
      );
    }
    try {
      final response = await dio.post('/ai/reprocess-stale-embeddings');
      return response.data['stale_item_count'] as int;
    } on DioException catch (e) {
      final detail = e.response?.data is Map ? e.response?.data['detail'] : null;
      throw UnexpectedFailure(
        detail as String? ?? 'Yeniden işleme başlatılamadı. Lütfen tekrar dene.',
      );
    }
  }
}
