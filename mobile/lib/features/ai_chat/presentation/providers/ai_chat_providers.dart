import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/network/api_client_provider.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/remote/api_ai_chat_repository.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/repositories/ai_chat_repository.dart';

final aiChatRepositoryProvider = Provider<AiChatRepository>((ref) {
  return ApiAiChatRepository(ref.watch(apiClientProvider));
});

/// Whether a question is currently in flight — the chat screen shows a
/// "typing..." bubble while this is true.
final isAskingProvider = StateProvider<bool>((ref) => false);

final chatControllerProvider =
    AsyncNotifierProvider<ChatController, List<ChatMessage>>(ChatController.new);

/// Holds the whole conversation, in memory only — a fresh session each
/// time the tab is opened. Errors become an error-flagged chat bubble
/// rather than an `AsyncError` state, so one failed question never wipes
/// the conversation so far.
class ChatController extends AsyncNotifier<List<ChatMessage>> {
  @override
  List<ChatMessage> build() {
    // P1-01 (docs/requirements-audit-2026-09-13.md): the conversation
    // used to survive a sign-out/sign-in inside the same app session —
    // a different account on the same device could see the previous
    // one's questions and answers until the chat screen happened to be
    // rebuilt from scratch. Any account change wipes it immediately.
    ref.listen(currentUserIdProvider, (previous, next) {
      if (previous != next) state = const AsyncData([]);
    });
    return [];
  }

  Future<void> ask(String question) async {
    final trimmed = question.trim();
    if (trimmed.isEmpty) return;

    // The conversation *before* this question — what P2-03 (docs/
    // requirements-audit-2026-09-13.md) sends the backend as context, so
    // a follow-up ("peki onun boyu?") makes sense to it the way it
    // already does to whoever's reading this screen.
    final priorMessages = state.valueOrNull ?? const <ChatMessage>[];
    final conversation = <ChatMessage>[
      ...priorMessages,
      ChatMessage(role: ChatRole.user, text: trimmed),
    ];
    state = AsyncData(conversation);

    ref.read(isAskingProvider.notifier).state = true;
    try {
      final result = await ref
          .read(aiChatRepositoryProvider)
          .ask(trimmed, history: priorMessages);
      state = AsyncData([
        ...conversation,
        ChatMessage(role: ChatRole.assistant, text: result.answer, sources: result.sources),
      ]);
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
