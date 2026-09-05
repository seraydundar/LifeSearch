import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../search/domain/entities/search_result.dart';

part 'rag_answer.freezed.dart';

@freezed
sealed class RagAnswer with _$RagAnswer {
  const factory RagAnswer({
    required String answer,
    required List<SearchResult> sources,
  }) = _RagAnswer;
}
