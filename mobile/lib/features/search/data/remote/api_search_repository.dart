import 'package:dio/dio.dart';

import '../../../../core/error/failure.dart';
import '../../../item/domain/entities/item.dart';
import '../../domain/entities/search_result.dart';
import '../../domain/repositories/search_repository.dart';

class ApiSearchRepository implements SearchRepository {
  ApiSearchRepository(this._dio);

  final Dio? _dio;

  @override
  Future<List<SearchResult>> search(String query) async {
    final dio = _dio;
    if (dio == null) {
      throw const UnexpectedFailure(
        'Arama şu anda kullanılamıyor. Backend bağlantısı ayarlanmamış.',
      );
    }

    try {
      final response = await dio.post('/search/', data: {'query': query});
      final results = response.data['results'] as List;
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
    } on DioException catch (e) {
      final detail = e.response?.data is Map ? e.response?.data['detail'] : null;
      throw UnexpectedFailure(detail as String? ?? 'Arama başarısız oldu. Lütfen tekrar dene.');
    }
  }
}
