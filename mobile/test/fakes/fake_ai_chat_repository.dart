import 'package:lifesearch/features/ai_chat/domain/entities/rag_answer.dart';
import 'package:lifesearch/features/ai_chat/domain/repositories/ai_chat_repository.dart';
import 'package:lifesearch/features/search/domain/entities/search_result.dart';

class FakeAiChatRepository implements AiChatRepository {
  FakeAiChatRepository({this.answerToReturn, this.errorToThrow});

  RagAnswer? answerToReturn;
  Object? errorToThrow;
  String? lastQuestion;

  @override
  Future<RagAnswer> ask(String question) async {
    lastQuestion = question;
    if (errorToThrow != null) throw errorToThrow!;
    return answerToReturn ??
        const RagAnswer(answer: 'Varsayılan cevap.', sources: <SearchResult>[]);
  }
}
