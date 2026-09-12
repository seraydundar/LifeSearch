import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesearch/features/item/domain/entities/item.dart';
import 'package:lifesearch/features/item/presentation/providers/item_providers.dart';
import 'package:lifesearch/features/search/presentation/providers/search_providers.dart';

import '../fakes/fake_item_repository.dart';
import '../fakes/fake_search_repository.dart';

/// Simulates a genuine failure to determine which items are private —
/// e.g. a Drift error — as opposed to the "unconfigured test fixture"
/// case `search_tab_test.dart`'s default `FakeItemRepository()` covers.
class _ThrowingItemRepository extends FakeItemRepository {
  @override
  Stream<List<Item>> watchItems() => Stream.error(Exception('boom'));
}

void main() {
  // Faz 12, madde 5 (denetim düzeltmesi — see docs/roadmap.md): two real,
  // previously-unfixed gaps in how search hides private items.
  group('SearchController private-item filtering', () {
    test(
        'a genuine failure to check which items are private fails the search closed '
        '(a real error state), not open (silently showing every result)', () async {
      final container = ProviderContainer(overrides: [
        searchRepositoryProvider.overrideWithValue(
          FakeSearchRepository(resultsToReturn: [fakeSearchResult()]),
        ),
        itemRepositoryProvider.overrideWithValue(_ThrowingItemRepository()),
      ]);
      addTearDown(container.dispose);

      await container.read(searchControllerProvider.notifier).search('docker');

      expect(container.read(searchControllerProvider).hasError, isTrue);
    });

    test(
        'a private result already on screen disappears once reveal turns back off — '
        "not just excluded from the *next* search (e.g. the app is backgrounded, see "
        "AppLockGate)", () async {
      final itemRepo = FakeItemRepository(initialItems: [
        Item(
          id: 'private-item',
          type: ItemType.note,
          title: 'Secret',
          processingStatus: 'completed',
          favorite: false,
          createdAt: DateTime(2026, 1, 1),
          private: true,
        ),
        Item(
          id: 'public-item',
          type: ItemType.note,
          title: 'Public',
          processingStatus: 'completed',
          favorite: false,
          createdAt: DateTime(2026, 1, 1),
        ),
      ]);
      final container = ProviderContainer(overrides: [
        searchRepositoryProvider.overrideWithValue(FakeSearchRepository(resultsToReturn: [
          fakeSearchResult(itemId: 'private-item'),
          fakeSearchResult(itemId: 'public-item'),
        ])),
        itemRepositoryProvider.overrideWithValue(itemRepo),
      ]);
      addTearDown(container.dispose);

      // Reveal private items, then search — both results show, private one included.
      container.read(privateItemsRevealedProvider.notifier).state = true;
      await container.read(searchControllerProvider.notifier).search('docker');
      expect(
        container.read(searchControllerProvider).valueOrNull?.map((r) => r.itemId).toSet(),
        {'private-item', 'public-item'},
      );

      // Reveal turns back off — the already-displayed list should drop
      // the private result immediately, without a new search.
      container.read(privateItemsRevealedProvider.notifier).state = false;
      await Future<void>.delayed(Duration.zero); // let the listener's async re-filter land

      final after = container.read(searchControllerProvider).valueOrNull;
      expect(after?.map((r) => r.itemId), ['public-item']);
    });
  });

  // Faz 12, madde 13 (denetim düzeltmesi — see docs/roadmap.md): nothing
  // previously stopped a slow, older search()'s response from landing
  // after a faster, newer one already updated state (or after clear()
  // reset it).
  group('SearchController race condition', () {
    test(
        "a slower, older search's response does not overwrite a faster, newer "
        'one that already resolved', () async {
      final gates = {'slow': Completer<void>(), 'fast': Completer<void>()};
      final repo = FakeSearchRepository(
        gates: gates,
        resultsByQuery: {
          'slow': [fakeSearchResult(itemId: 'slow-result')],
          'fast': [fakeSearchResult(itemId: 'fast-result')],
        },
      );
      final container = ProviderContainer(overrides: [
        searchRepositoryProvider.overrideWithValue(repo),
        itemRepositoryProvider.overrideWithValue(FakeItemRepository()),
      ]);
      addTearDown(container.dispose);
      final controller = container.read(searchControllerProvider.notifier);

      // The user types "slow", then quickly changes their mind and types
      // "fast" before the first request comes back.
      final slowFuture = controller.search('slow');
      final fastFuture = controller.search('fast');

      // "fast" wins the race and lands first...
      gates['fast']!.complete();
      await fastFuture;
      expect(
        container.read(searchControllerProvider).valueOrNull?.map((r) => r.itemId),
        ['fast-result'],
      );

      // ...then "slow"'s response finally arrives, late. It must not
      // clobber the newer result already on screen.
      gates['slow']!.complete();
      await slowFuture;
      expect(
        container.read(searchControllerProvider).valueOrNull?.map((r) => r.itemId),
        ['fast-result'],
      );
    });

    test("clear() invalidates an in-flight search so its late result can't reappear",
        () async {
      final gate = Completer<void>();
      final repo = FakeSearchRepository(
        gates: {'query': gate},
        resultsToReturn: [fakeSearchResult()],
      );
      final container = ProviderContainer(overrides: [
        searchRepositoryProvider.overrideWithValue(repo),
        itemRepositoryProvider.overrideWithValue(FakeItemRepository()),
      ]);
      addTearDown(container.dispose);
      final controller = container.read(searchControllerProvider.notifier);

      final searchFuture = controller.search('query');
      controller.clear();
      expect(container.read(searchControllerProvider).valueOrNull, isEmpty);

      // The in-flight search finally resolves after the field was
      // already cleared — it must not repopulate the (now empty) list.
      gate.complete();
      await searchFuture;
      expect(container.read(searchControllerProvider).valueOrNull, isEmpty);
    });
  });
}
