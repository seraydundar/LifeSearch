import '../entities/rag_answer.dart';

abstract interface class AiChatRepository {
  Future<RagAnswer> ask(String question);
}
