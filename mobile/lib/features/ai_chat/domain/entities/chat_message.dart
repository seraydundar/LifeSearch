import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../search/domain/entities/search_result.dart';

part 'chat_message.freezed.dart';

enum ChatRole { user, assistant }

/// One turn in the "Ask AI" conversation; `sources` is empty for user
/// messages and for answers that found nothing to cite.
@freezed
sealed class ChatMessage with _$ChatMessage {
  const factory ChatMessage({
    required ChatRole role,
    required String text,
    @Default([]) List<SearchResult> sources,
    @Default(false) bool isError,
  }) = _ChatMessage;
}
