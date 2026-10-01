import '../entities/chat_message.dart';
import '../entities/rag_answer.dart';

abstract interface class AiChatRepository {
  /// [history] is the conversation so far, oldest first, not including
  /// [question] — lets follow-up questions make sense to the backend.
  Future<RagAnswer> ask(String question, {List<ChatMessage> history = const []});
}
