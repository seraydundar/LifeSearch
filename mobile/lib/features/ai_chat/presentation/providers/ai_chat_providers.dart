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

/// Whether a question is currently in flight — the chat screen shows a
/// "typing..." bubble while this is true.
final isAskingProvider = StateProvider<bool>((ref) => false);

final chatControllerProvider =
    AsyncNotifierProvider<ChatController, List<ChatMessage>>(ChatController.new);

/// Holds the whole conversation — persisted locally (Faz 36, docs/
/// roadmap.md) so it survives an app restart, which it used to lose
/// entirely (in-memory-only state). Errors become an error-flagged chat
/// bubble rather than an `AsyncError` state, so one failed question
/// never wipes the conversation so far; error bubbles themselves are
/// never persisted, same reasoning `ApiAiChatRepository.ask` already
/// uses to exclude them from the history sent to the backend.
class ChatController extends AsyncNotifier<List<ChatMessage>> {
  @override
  Future<List<ChatMessage>> build() async {
    // P1-01 (docs/requirements-audit-2026-09-13.md): a different account
    // on the same device must never see the previous one's questions and
    // answers. Scoping every row by `userId` already prevents that at
    // the storage layer, so an account change just needs to reload *its
    // own* history (possibly none) instead of the in-memory list's old
    // force-to-empty — which would otherwise erase a returning account's
    // real saved conversation.
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

    // Read lazily, only once actually needed below — not every test (or
    // signed-out) setup has a real `appDatabaseProvider` to read from,
    // and there's nothing to persist for either case anyway.
    final userId = ref.read(currentUserIdProvider);

    // The conversation *before* this question — what P2-03 (docs/
    // requirements-audit-2026-09-13.md) sends the backend as context, so
    // a follow-up ("peki onun boyu?") makes sense to it the way it
    // already does to whoever's reading this screen.
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
