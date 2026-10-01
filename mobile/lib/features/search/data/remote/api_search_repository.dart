import 'package:dio/dio.dart';

import '../../../../core/error/failure.dart';
import '../../../item/domain/entities/item.dart';
import '../../domain/entities/search_filters.dart';
import '../../domain/entities/search_result.dart';
import '../../domain/repositories/search_repository.dart';

class ApiSearchRepository implements SearchRepository {
  ApiSearchRepository(this._dio);

  final Dio? _dio;

  Dio _requireDio() {
    final dio = _dio;
    if (dio == null) {
      throw const UnexpectedFailure(
        'Arama şu anda kullanılamıyor. Backend bağlantısı ayarlanmamış.',
      );
    }
    return dio;
  }

  List<SearchResult> _parseResults(dynamic data) {
    final results = data['results'] as List;
    return results.map((row) {
      final map = row as Map<String, dynamic>;
      return SearchResult(
        itemId: map['item_id'] as String,
        itemType: ItemTypeX.fromDbValue(map['item_type'] as String),
        itemTitle: map['item_title'] as String?,
        snippet: map['snippet'] as String,
        similarity: (map['similarity'] as num).toDouble(),
      );
    }).toList();
  }

  Never _throwFromDioError(DioException e, String fallback) {
    final detail = e.response?.data is Map ? e.response?.data['detail'] : null;
    throw UnexpectedFailure(detail as String? ?? fallback);
  }

  @override
  Future<List<SearchResult>> search(
    String query, {
    SearchFilters filters = const SearchFilters(),
    bool includePrivate = false,
  }) async {
    final dio = _requireDio();
    try {
      final response = await dio.post('/search/', data: {
        'query': query,
        if (filters.types.isNotEmpty) 'item_types': filters.types.map((t) => t.dbValue).toList(),
        // `.toUtc()` first: bare `toIso8601String()` omits the offset, which the backend
        // would otherwise misread as already being UTC.
        if (filters.dateFrom != null) 'date_from': filters.dateFrom!.toUtc().toIso8601String(),
        if (filters.dateTo != null) 'date_to': filters.dateTo!.toUtc().toIso8601String(),
        'include_private': includePrivate,
        // Lets the backend's free-text date parser ("bugün", "dün") use the client's local day.
        'timezone_offset_minutes': DateTime.now().timeZoneOffset.inMinutes,
      });
      return _parseResults(response.data);
    } on DioException catch (e) {
      _throwFromDioError(e, 'Arama başarısız oldu. Lütfen tekrar dene.');
    }
  }

  @override
  Future<List<SearchResult>> related(String itemId, {bool includePrivate = false}) async {
    final dio = _requireDio();
    try {
      final response = await dio.post('/search/related', data: {
        'item_id': itemId,
        'include_private': includePrivate,
      });
      return _parseResults(response.data);
    } on DioException catch (e) {
      _throwFromDioError(e, 'İlgili içerikler yüklenemedi.');
    }
  }
}
