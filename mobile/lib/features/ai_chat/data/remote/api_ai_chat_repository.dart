import 'package:dio/dio.dart';

import '../../../../core/error/failure.dart';
import '../../../item/domain/entities/item.dart';
import '../../../search/domain/entities/search_result.dart';
import '../../domain/entities/rag_answer.dart';
import '../../domain/repositories/ai_chat_repository.dart';

class ApiAiChatRepository implements AiChatRepository {
  ApiAiChatRepository(this._dio);

  final Dio? _dio;

  @override
  Future<RagAnswer> ask(String question) async {
    final dio = _dio;
    if (dio == null) {
      throw const UnexpectedFailure(
        'Ask AI şu anda kullanılamıyor. Backend bağlantısı ayarlanmamış.',
      );
    }

    try {
      final response = await dio.post('/ai/ask', data: {'question': question});
      final data = response.data as Map<String, dynamic>;
      final sources = (data['sources'] as List).map((row) {
        final map = row as Map<String, dynamic>;
        return SearchResult(
          itemId: map['item_id'] as String,
          itemType: ItemTypeX.fromDbValue(map['item_type'] as String),
          itemTitle: map['item_title'] as String?,
          snippet: map['snippet'] as String,
          similarity: (map['similarity'] as num).toDouble(),
        );
      }).toList();
      return RagAnswer(answer: data['answer'] as String, sources: sources);
    } on DioException catch (e) {
      final detail = e.response?.data is Map ? e.response?.data['detail'] : null;
      throw UnexpectedFailure(detail as String? ?? 'Soru yanıtlanamadı. Lütfen tekrar dene.');
    }
  }
}
