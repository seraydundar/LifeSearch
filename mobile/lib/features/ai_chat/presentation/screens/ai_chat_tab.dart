import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../item/domain/entities/item.dart';
import '../../../item/presentation/widgets/item_type_icon.dart';
import '../../../search/domain/entities/search_result.dart';
import '../../domain/entities/chat_message.dart';
import '../providers/ai_chat_providers.dart';

/// "Ask AI" — RAG chat over the user's own archive.
class AiChatTab extends ConsumerStatefulWidget {
  const AiChatTab({super.key});

  @override
  ConsumerState<AiChatTab> createState() => _AiChatTabState();
}

class _AiChatTabState extends ConsumerState<AiChatTab>
    with AutomaticKeepAliveClientMixin<AiChatTab> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    _controller.clear();
    ref.read(chatControllerProvider.notifier).ask(text);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _openSource(SearchResult source) {
    final route =
        source.itemType == ItemType.note ? '/item/${source.itemId}/note' : '/item/${source.itemId}';
    context.push(
      route,
      extra: Item(
        id: source.itemId,
        type: source.itemType,
        title: source.itemTitle,
        processingStatus: 'completed',
        favorite: false,
        createdAt: DateTime.now(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final messages = ref.watch(chatControllerProvider).valueOrNull ?? [];
    final isAsking = ref.watch(isAskingProvider);

    return Column(
      children: [
        Expanded(
          child: messages.isEmpty
              ? const _EmptyState()
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length + (isAsking ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == messages.length) {
                      return const _TypingBubble();
                    }
                    return _MessageBubble(message: messages[index], onOpenSource: _openSource);
                  },
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: 'Arşivin hakkında bir şey sor...',
                      filled: true,
                      fillColor:
                          Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: isAsking ? null : _send,
                  icon: const Icon(Icons.arrow_upward),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_awesome_outlined,
              size: 36,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'Arşivin hakkında soru sor.\nÖrn: "Docker hakkında neler kaydetmişim?"',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.onOpenSource});

  final ChatMessage message;
  final ValueChanged<SearchResult> onOpenSource;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == ChatRole.user;
    final theme = Theme.of(context);
    final bubbleColor = isUser
        ? theme.colorScheme.primary
        : message.isError
            ? theme.colorScheme.errorContainer
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6);
    final textColor = isUser ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
        child: Column(
          crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 6),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(color: bubbleColor, borderRadius: BorderRadius.circular(16)),
              child: Text(message.text, style: TextStyle(color: textColor)),
            ),
            if (message.sources.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 4),
                child: Text('Sources', style: theme.textTheme.labelSmall),
              ),
              ...message.sources.map(
                (source) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: ActionChip(
                    avatar: Icon(
                      itemTypeIcon(source.itemType),
                      size: 16,
                      color: itemTypeColor(source.itemType),
                    ),
                    label: Text(
                      source.itemTitle ?? 'Untitled',
                      overflow: TextOverflow.ellipsis,
                    ),
                    onPressed: () => onOpenSource(source),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
