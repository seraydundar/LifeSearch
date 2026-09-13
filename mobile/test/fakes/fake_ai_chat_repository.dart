import 'package:lifesearch/features/ai_chat/domain/entities/chat_message.dart';
import 'package:lifesearch/features/ai_chat/domain/entities/rag_answer.dart';
import 'package:lifesearch/features/ai_chat/domain/repositories/ai_chat_repository.dart';
import 'package:lifesearch/features/search/domain/entities/search_result.dart';

class FakeAiChatRepository implements AiChatRepository {
  FakeAiChatRepository({this.answerToReturn, this.errorToThrow});

  RagAnswer? answerToReturn;
  Object? errorToThrow;
  String? lastQuestion;
  List<ChatMessage>? lastHistory;

  @override
  Future<RagAnswer> ask(String question, {List<ChatMessage> history = const []}) async {
    lastQuestion = question;
    lastHistory = history;
    if (errorToThrow != null) throw errorToThrow!;
    return answerToReturn ??
        const RagAnswer(answer: 'Varsayılan cevap.', sources: <SearchResult>[]);
  }
}
