import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/network/api_client_provider.dart';
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
  List<ChatMessage> build() => [];

  Future<void> ask(String question) async {
    final trimmed = question.trim();
    if (trimmed.isEmpty) return;

    final history = <ChatMessage>[
      ...state.valueOrNull ?? const <ChatMessage>[],
      ChatMessage(role: ChatRole.user, text: trimmed),
    ];
    state = AsyncData(history);

    ref.read(isAskingProvider.notifier).state = true;
    try {
      final result = await ref.read(aiChatRepositoryProvider).ask(trimmed);
      state = AsyncData([
        ...history,
        ChatMessage(role: ChatRole.assistant, text: result.answer, sources: result.sources),
      ]);
    } catch (e) {
      final message = e is Failure ? e.message : 'Bir hata oluştu.';
      state = AsyncData([
        ...history,
        ChatMessage(role: ChatRole.assistant, text: message, isError: true),
      ]);
    } finally {
      ref.read(isAskingProvider.notifier).state = false;
    }
  }
}
