import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_provider.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/network/api_client_provider.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/local/chat_messages_data_source.dart';
import '../../data/remote/api_ai_chat_repository.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/repositories/ai_chat_repository.dart';

final aiChatRepositoryProvider = Provider<AiChatRepository>((ref) {
  return ApiAiChatRepository(ref.watch(apiClientProvider));
});

final chatMessagesDataSourceProvider = Provider<ChatMessagesDataSource>((ref) {
  return ChatMessagesDataSource(ref.watch(appDatabaseProvider));
});

/// True while a question is in flight; drives the "typing..." bubble.
final isAskingProvider = StateProvider<bool>((ref) => false);

final chatControllerProvider =
    AsyncNotifierProvider<ChatController, List<ChatMessage>>(ChatController.new);

/// Holds the whole conversation, persisted locally. Errors become an
/// error-flagged bubble rather than an `AsyncError` state, so one failed
/// question doesn't wipe the conversation; error bubbles are never persisted.
class ChatController extends AsyncNotifier<List<ChatMessage>> {
  @override
  Future<List<ChatMessage>> build() async {
    // Reload (not force-clear) on account change: rows are scoped by userId, so a
    // returning account should see its own saved history, not an empty list.
    ref.listen(currentUserIdProvider, (previous, next) {
      if (previous != next) ref.invalidateSelf();
    });

    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return const [];
    return ref.read(chatMessagesDataSourceProvider).loadAll(userId);
  }

  Future<void> ask(String question) async {
    final trimmed = question.trim();
    if (trimmed.isEmpty) return;

    // Lazy read: not every test/signed-out setup has a real appDatabaseProvider.
    final userId = ref.read(currentUserIdProvider);

    // Conversation before this question, sent to the backend as context for follow-ups.
    final priorMessages = state.valueOrNull ?? const <ChatMessage>[];
    final userMessage = ChatMessage(role: ChatRole.user, text: trimmed);
    final conversation = <ChatMessage>[...priorMessages, userMessage];
    state = AsyncData(conversation);
    if (userId != null) {
      unawaited(ref.read(chatMessagesDataSourceProvider).append(userId, userMessage));
    }

    ref.read(isAskingProvider.notifier).state = true;
    try {
      final result = await ref
          .read(aiChatRepositoryProvider)
          .ask(trimmed, history: priorMessages);
      final assistantMessage =
          ChatMessage(role: ChatRole.assistant, text: result.answer, sources: result.sources);
      state = AsyncData([...conversation, assistantMessage]);
      if (userId != null) {
        unawaited(ref.read(chatMessagesDataSourceProvider).append(userId, assistantMessage));
      }
    } catch (e) {
      final message = e is Failure ? e.message : 'Bir hata oluştu.';
      state = AsyncData([
        ...conversation,
        ChatMessage(role: ChatRole.assistant, text: message, isError: true),
      ]);
    } finally {
      ref.read(isAskingProvider.notifier).state = false;
    }
  }
}
