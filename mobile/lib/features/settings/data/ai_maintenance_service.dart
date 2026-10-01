import 'package:dio/dio.dart';

import '../../../core/error/failure.dart';

/// User-triggered only (Settings' "AI Status" row), never automatic — bulk re-embedding is a real AI-cost spike.
class AiMaintenanceService {
  AiMaintenanceService(this._dio);

  final Dio? _dio;

  /// Count of items scheduled, not completed — the backend processes them async after returning 202.
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
