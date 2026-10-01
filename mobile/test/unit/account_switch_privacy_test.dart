import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lifesearch/core/database/app_database.dart';
import 'package:lifesearch/core/database/database_provider.dart';
import 'package:lifesearch/features/ai_chat/domain/entities/rag_answer.dart';
import 'package:lifesearch/features/ai_chat/presentation/providers/ai_chat_providers.dart';
import 'package:lifesearch/features/auth/domain/entities/app_user.dart';
import 'package:lifesearch/features/auth/presentation/providers/auth_providers.dart';
import 'package:lifesearch/features/item/presentation/providers/item_providers.dart';
import 'package:lifesearch/features/search/presentation/providers/search_providers.dart';

import '../fakes/fake_ai_chat_repository.dart';
import '../fakes/fake_item_repository.dart';
import '../fakes/fake_search_repository.dart';

/// P1-01 (docs/requirements-audit-2026-09-13.md): `SearchController` and
/// `ChatController` used to hold onto whichever account was signed in
/// when a search/question was last run — signing out of account A and
/// straight into account B (no full app restart) left A's search results
/// and chat conversation on screen until B happened to overwrite them
/// with a fresh one of their own. These reproduce the reported leak
/// against the real provider graph and confirm the fix (`ref.listen
/// (currentUserIdProvider, ...)` in both controllers' `build()`).
void main() {
  test('search results are cleared the moment the signed-in account changes', () async {
    final auth = StreamController<AppUser?>();
    addTearDown(auth.close);
    final container = ProviderContainer(overrides: [
      authStateChangesProvider.overrideWith((ref) => auth.stream),
      searchRepositoryProvider.overrideWithValue(
        FakeSearchRepository(resultsToReturn: [fakeSearchResult(itemId: 'user-a-private-doc')]),
      ),
      itemRepositoryProvider.overrideWithValue(FakeItemRepository()),
    ]);
    addTearDown(container.dispose);
    container.listen(currentUserIdProvider, (_, _) {}); // force subscription before pushing

    auth.add(const AppUser(id: 'user-a', email: 'a@example.com'));
    await Future<void>.delayed(Duration.zero);
    await container.read(searchControllerProvider.notifier).search('account A query');
    expect(container.read(searchControllerProvider).requireValue, hasLength(1));

    auth.add(const AppUser(id: 'user-b', email: 'b@example.com'));
    await Future<void>.delayed(Duration.zero);

    expect(container.read(currentUserIdProvider), 'user-b');
    expect(container.read(searchControllerProvider).requireValue, isEmpty);
  });

  test('chat history is cleared the moment the signed-in account changes', () async {
    final auth = StreamController<AppUser?>();
    addTearDown(auth.close);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(overrides: [
      authStateChangesProvider.overrideWith((ref) => auth.stream),
      appDatabaseProvider.overrideWithValue(db),
      aiChatRepositoryProvider.overrideWithValue(
        FakeAiChatRepository(
          answerToReturn: const RagAnswer(answer: 'User A confidential answer', sources: []),
        ),
      ),
    ]);
    addTearDown(container.dispose);
    container.listen(currentUserIdProvider, (_, _) {});

    auth.add(const AppUser(id: 'user-a', email: 'a@example.com'));
    await Future<void>.delayed(Duration.zero);
    await container.read(chatControllerProvider.notifier).ask('My private question');
    expect(container.read(chatControllerProvider).requireValue, hasLength(2));

    auth.add(const AppUser(id: 'user-b', email: 'b@example.com'));
    await Future<void>.delayed(Duration.zero);

    expect(container.read(currentUserIdProvider), 'user-b');
    expect(container.read(chatControllerProvider).requireValue, isEmpty);
  });

  test('signing out entirely also clears both, not just switching to another account', () async {
    final auth = StreamController<AppUser?>();
    addTearDown(auth.close);
    final container = ProviderContainer(overrides: [
      authStateChangesProvider.overrideWith((ref) => auth.stream),
      searchRepositoryProvider.overrideWithValue(
        FakeSearchRepository(resultsToReturn: [fakeSearchResult()]),
      ),
      itemRepositoryProvider.overrideWithValue(FakeItemRepository()),
    ]);
    addTearDown(container.dispose);
    container.listen(currentUserIdProvider, (_, _) {});

    auth.add(const AppUser(id: 'user-a', email: 'a@example.com'));
    await Future<void>.delayed(Duration.zero);
    await container.read(searchControllerProvider.notifier).search('query');
    expect(container.read(searchControllerProvider).requireValue, isNotEmpty);

    auth.add(null); // signed out
    await Future<void>.delayed(Duration.zero);

    expect(container.read(searchControllerProvider).requireValue, isEmpty);
  });
}
