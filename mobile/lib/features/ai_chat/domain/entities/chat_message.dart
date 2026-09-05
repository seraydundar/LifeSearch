import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../search/domain/entities/search_result.dart';

part 'chat_message.freezed.dart';

enum ChatRole { user, assistant }

/// One turn in the "Ask AI" conversation. An assistant message's
/// `sources` are the archive items its answer actually came from
/// (requirements doc, section 24) — empty for a user message, and for an
/// assistant message that found nothing to answer from.
@freezed
sealed class ChatMessage with _$ChatMessage {
  const factory ChatMessage({
    required ChatRole role,
    required String text,
    @Default([]) List<SearchResult> sources,
    @Default(false) bool isError,
  }) = _ChatMessage;
}
