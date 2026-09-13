import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesearch/features/auth/domain/entities/app_user.dart';
import 'package:lifesearch/features/auth/presentation/providers/auth_providers.dart';
import 'package:lifesearch/features/ai_chat/domain/entities/rag_answer.dart';
import 'package:lifesearch/features/ai_chat/presentation/providers/ai_chat_providers.dart';
import 'package:lifesearch/features/item/presentation/providers/item_providers.dart';
import 'package:lifesearch/features/search/presentation/providers/search_providers.dart';
import '../fakes/fake_ai_chat_repository.dart';
import '../fakes/fake_item_repository.dart';
import '../fakes/fake_search_repository.dart';

void main() {
  test('AUDIT search results should clear when account changes', () async {
    final auth = StreamController<AppUser?>();
    final container = ProviderContainer(overrides: [
      authStateChangesProvider.overrideWith((ref) => auth.stream),
      searchRepositoryProvider.overrideWithValue(FakeSearchRepository(
        resultsToReturn: [fakeSearchResult(itemId: 'user-a-private-document')],
      )),
      itemRepositoryProvider.overrideWithValue(FakeItemRepository()),
    ]);
    addTearDown(auth.close);
    addTearDown(container.dispose);
    container.listen(currentUserIdProvider, (_, next) {});
    auth.add(const AppUser(id: 'user-a', email: 'a@example.com'));
    await Future<void>.delayed(Duration.zero);
    await container.read(searchControllerProvider.notifier).search('account A query');
    expect(container.read(searchControllerProvider).requireValue, hasLength(1));
    auth.add(null);
    await Future<void>.delayed(Duration.zero);
    auth.add(const AppUser(id: 'user-b', email: 'b@example.com'));
    await Future<void>.delayed(Duration.zero);
    expect(container.read(currentUserIdProvider), 'user-b');
    expect(container.read(searchControllerProvider).requireValue, isEmpty);
  });

  test('AUDIT chat history should clear when account changes', () async {
    final auth = StreamController<AppUser?>();
    final container = ProviderContainer(overrides: [
      authStateChangesProvider.overrideWith((ref) => auth.stream),
      aiChatRepositoryProvider.overrideWithValue(FakeAiChatRepository(
        answerToReturn: const RagAnswer(answer: 'User A confidential answer', sources: []),
      )),
    ]);
    addTearDown(auth.close);
    addTearDown(container.dispose);
    container.listen(currentUserIdProvider, (_, next) {});
    auth.add(const AppUser(id: 'user-a', email: 'a@example.com'));
    await Future<void>.delayed(Duration.zero);
    await container.read(chatControllerProvider.notifier).ask('My private question');
    expect(container.read(chatControllerProvider).requireValue, hasLength(2));
    auth.add(null);
    await Future<void>.delayed(Duration.zero);
    auth.add(const AppUser(id: 'user-b', email: 'b@example.com'));
    await Future<void>.delayed(Duration.zero);
    expect(container.read(currentUserIdProvider), 'user-b');
    expect(container.read(chatControllerProvider).requireValue, isEmpty);
  });

  test('AUDIT unknown privacy status should not show remote snippet', () async {
    final container = ProviderContainer(overrides: [
      searchRepositoryProvider.overrideWithValue(FakeSearchRepository(
        resultsToReturn: [fakeSearchResult(itemId: 'unsynced-private-item')],
      )),
      itemRepositoryProvider.overrideWithValue(FakeItemRepository()),
    ]);
    addTearDown(container.dispose);
    expect(container.read(privateItemsRevealedProvider), isFalse);
    await container.read(searchControllerProvider.notifier).search('confidential');
    expect(container.read(searchControllerProvider).requireValue, isEmpty);
  });
}
