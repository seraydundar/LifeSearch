import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesearch/core/error/failure.dart';
import 'package:lifesearch/features/ai_chat/domain/entities/rag_answer.dart';
import 'package:lifesearch/features/ai_chat/presentation/providers/ai_chat_providers.dart';
import 'package:lifesearch/features/ai_chat/presentation/screens/ai_chat_tab.dart';
import 'package:lifesearch/features/item/domain/entities/item.dart';
import 'package:lifesearch/features/search/domain/entities/search_result.dart';

import '../fakes/fake_ai_chat_repository.dart';

void main() {
  Widget wrap(FakeAiChatRepository repo) {
    return ProviderScope(
      overrides: [aiChatRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: Scaffold(body: AiChatTab())),
    );
  }

  testWidgets('shows a prompt before any question is asked', (tester) async {
    await tester.pumpWidget(wrap(FakeAiChatRepository()));
    await tester.pumpAndSettle();

    expect(find.textContaining('Arşivin hakkında soru sor'), findsOneWidget);
  });

  testWidgets('asking a question shows the user bubble then the answer', (tester) async {
    final repo = FakeAiChatRepository(
      answerToReturn: const RagAnswer(
        answer: "Docker Compose birden fazla container'ı yönetir.",
        sources: [
          SearchResult(
            itemId: 'note-1',
            itemType: ItemType.note,
            itemTitle: 'Docker Notes',
            snippet: 'Docker Compose...',
            similarity: 0.9,
          ),
        ],
      ),
    );
    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Docker compose nedir?');
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pumpAndSettle();

    expect(repo.lastQuestion, 'Docker compose nedir?');
    expect(find.text('Docker compose nedir?'), findsOneWidget);
    expect(find.textContaining('birden fazla'), findsOneWidget);
    expect(find.text('Docker Notes'), findsOneWidget); // the source chip
  });

  testWidgets('a failed question shows an error bubble, not a crash', (tester) async {
    final repo = FakeAiChatRepository(
      errorToThrow: const UnexpectedFailure('Ask AI şu anda kullanılamıyor.'),
    );
    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'soru');
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pumpAndSettle();

    expect(find.text('Ask AI şu anda kullanılamıyor.'), findsOneWidget);
  });
}
