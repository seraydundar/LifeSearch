import '../entities/chat_message.dart';
import '../entities/rag_answer.dart';

abstract interface class AiChatRepository {
  /// [history] is the conversation so far, oldest first, **not including**
  /// [question] itself — lets a follow-up ("peki onun boyu?") make sense
  /// to the backend the way it already does to whoever's reading the chat
  /// screen (P2-03, docs/requirements-audit-2026-09-13.md). Previously
  /// unused entirely: every question was answered as if it were the first
  /// one asked.
  Future<RagAnswer> ask(String question, {List<ChatMessage> history = const []});
}
