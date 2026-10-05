import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lifesearch/features/item/domain/entities/item.dart';
import 'package:lifesearch/features/item/presentation/providers/item_providers.dart';
import 'package:lifesearch/features/item/presentation/screens/item_detail_screen.dart';
import 'package:lifesearch/features/search/presentation/providers/search_providers.dart';
import 'package:lifesearch/features/settings/presentation/providers/app_lock_providers.dart';

import '../fakes/fake_app_lock_service.dart';
import '../fakes/fake_item_repository.dart';
import '../fakes/fake_search_repository.dart';

void main() {
  Widget wrap(Item openedWith, {FakeItemRepository? repo, List<Override> extraOverrides = const []}) {
    return ProviderScope(
      overrides: [
        itemRepositoryProvider.overrideWithValue(repo ?? FakeItemRepository()),
        searchRepositoryProvider.overrideWithValue(FakeSearchRepository()),
        ...extraOverrides,
      ],
      child: MaterialApp(home: ItemDetailScreen(item: openedWith)),
    );
  }

  /// The trimmed stand-in `Item` Search/Ask AI/Related Items construct —
  /// see `search_tab.dart`'s `_openResult` — carries an id/type/title and
  /// nothing else a file-backed item actually needs.
  Item trimmedStandIn({required String id, ItemType type = ItemType.pdf}) {
    return Item(
      id: id,
      type: type,
      title: 'Untitled from search',
      processingStatus: 'completed',
      favorite: false,
      createdAt: DateTime.now(),
    );
  }

  testWidgets('the private toggle marks and unmarks an item, no auth needed either way',
      (tester) async {
    final item = Item(
      id: 'item-1',
      type: ItemType.note,
      title: 'A note',
      processingStatus: 'completed',
      favorite: false,
      createdAt: DateTime(2026, 1, 1),
    );
    final repo = FakeItemRepository(initialItems: [item]);

    await tester.pumpWidget(wrap(item, repo: repo));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.lock_open_outlined), findsOneWidget);

    await tester.tap(find.byIcon(Icons.lock_open_outlined));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    expect((await repo.findById('item-1'))!.private, isTrue);

    await tester.tap(find.byIcon(Icons.lock_outline));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.lock_open_outlined), findsOneWidget);
    expect((await repo.findById('item-1'))!.private, isFalse);
  });

  testWidgets('an item already tapped from Library (storagePath already known) shows Open File immediately',
      (tester) async {
    final full = Item(
      id: 'item-1',
      type: ItemType.pdf,
      title: 'Backend Notes',
      originalFilename: 'backend-notes.pdf',
      storagePath: 'user/1/backend-notes.pdf',
      processingStatus: 'completed',
      favorite: false,
      createdAt: DateTime(2026, 1, 1),
    );

    await tester.pumpWidget(wrap(full, repo: FakeItemRepository(initialItems: [full])));
    await tester.pumpAndSettle();

    expect(find.text('Dosyayı Aç'), findsOneWidget);
  });

  // P2-09 (docs/requirements-audit-2026-09-13.md): a failed signed-URL
  // fetch used to leave the button disabled forever, indistinguishable
  // from "still loading" — no visible error, no way to retry short of
  // leaving and reopening the screen.
  testWidgets('a failed signed URL fetch shows a retry affordance, not a stuck disabled button',
      (tester) async {
    final full = Item(
      id: 'item-1',
      type: ItemType.pdf,
      title: 'Backend Notes',
      originalFilename: 'backend-notes.pdf',
      storagePath: 'user/1/backend-notes.pdf',
      processingStatus: 'completed',
      favorite: false,
      createdAt: DateTime(2026, 1, 1),
    );
    final repo = FakeItemRepository(initialItems: [full])
      ..getSignedUrlError = Exception('network error');

    await tester.pumpWidget(wrap(full, repo: repo));
    await tester.pumpAndSettle();

    expect(find.text('Dosyayı Aç'), findsNothing);
    expect(find.textContaining('Tekrar Dene'), findsOneWidget);

    repo.getSignedUrlError = null; // the network recovers
    await tester.tap(find.textContaining('Tekrar Dene'));
    await tester.pumpAndSettle();

    expect(find.text('Dosyayı Aç'), findsOneWidget);
    expect(repo.getSignedUrlCallCount, 2);
  });

  testWidgets(
      'a trimmed stand-in from search adopts the real local item — Open File appears once resolved',
      (tester) async {
    // The local cache already has the *real* item (synced earlier) — this
    // is the common case: search results reference items this device
    // already knows about.
    final full = Item(
      id: 'item-1',
      type: ItemType.pdf,
      title: 'Backend Notes',
      originalFilename: 'backend-notes.pdf',
      storagePath: 'user/1/backend-notes.pdf',
      processingStatus: 'completed',
      favorite: true,
      createdAt: DateTime(2026, 1, 1),
    );

    await tester.pumpWidget(
      wrap(trimmedStandIn(id: 'item-1'), repo: FakeItemRepository(initialItems: [full])),
    );

    // Before findById() resolves, only what the stand-in itself carried.
    expect(find.text('Untitled from search'), findsOneWidget);
    expect(find.text('Dosyayı Aç'), findsNothing);

    await tester.pumpAndSettle();

    // Once resolved: the real title, the file-open button (needed the real
    // storagePath), and the real favorite star (the stand-in always fakes
    // `favorite: false`).
    expect(find.text('Backend Notes'), findsOneWidget);
    expect(find.text('Dosyayı Aç'), findsOneWidget);
    expect(find.byIcon(Icons.star), findsOneWidget); // favorited, not star_border
  });

  testWidgets('a failed item shows a Tekrar Dene button that re-triggers processing',
      (tester) async {
    final failed = Item(
      id: 'item-1',
      type: ItemType.pdf,
      title: 'Corrupt scan',
      originalFilename: 'scan.pdf',
      processingStatus: 'failed',
      favorite: false,
      createdAt: DateTime(2026, 1, 1),
    );
    final repo = FakeItemRepository(initialItems: [failed]);

    await tester.pumpWidget(wrap(failed, repo: repo));
    await tester.pumpAndSettle();

    expect(find.text('İşlenemedi'), findsOneWidget);
    expect(find.text('Tekrar Dene'), findsOneWidget);

    await tester.tap(find.text('Tekrar Dene'));
    await tester.pumpAndSettle();

    expect(repo.retryProcessingCallCount, 1);
    // Optimistically reflects the fresh attempt — the 'failed' chip is
    // gone, no more retry button to tap twice.
    expect(find.text('İşlenemedi'), findsNothing);
    expect(find.text('Tekrar Dene'), findsNothing);
    expect(find.text('İşlenmeyi bekliyor'), findsOneWidget);
  });

  testWidgets('a pending or completed item never shows a Tekrar Dene button', (tester) async {
    final pending = Item(
      id: 'item-1',
      type: ItemType.pdf,
      title: 'Still processing',
      processingStatus: 'pending',
      favorite: false,
      createdAt: DateTime(2026, 1, 1),
    );

    await tester.pumpWidget(wrap(pending, repo: FakeItemRepository(initialItems: [pending])));
    await tester.pumpAndSettle();

    expect(find.text('Tekrar Dene'), findsNothing);
  });

  testWidgets(
      'processing finishing while the screen is already open updates it live, no navigating away '
      'and back required (Faz 12, madde 8 — see docs/roadmap.md)', (tester) async {
    final pending = Item(
      id: 'item-1',
      type: ItemType.pdf,
      title: 'Still processing',
      processingStatus: 'pending',
      favorite: false,
      createdAt: DateTime(2026, 1, 1),
    );
    final repo = FakeItemRepository(initialItems: [pending]);

    await tester.pumpWidget(wrap(pending, repo: repo));
    await tester.pumpAndSettle();

    expect(find.text('İşlenmeyi bekliyor'), findsOneWidget);
    expect(find.text('Dosyayı Aç'), findsNothing);

    // The backend finishes processing — a background SyncService pull
    // would apply exactly this kind of update while the screen sits
    // there untouched, nothing re-navigated or manually refreshed.
    repo.updateItem(pending.copyWith(
      processingStatus: 'completed',
      storagePath: 'user/1/report.pdf',
    ));
    await tester.pumpAndSettle();

    expect(find.text('İşlenmeyi bekliyor'), findsNothing);
    expect(find.text('Dosyayı Aç'), findsOneWidget);
  });

  testWidgets(
      'processing finishing while the screen is open also refreshes tags/entities, not just '
      'the processing chip (denetim düzeltmesi — see docs/roadmap.md)', (tester) async {
    final pending = Item(
      id: 'item-1',
      type: ItemType.pdf,
      title: 'Still processing',
      processingStatus: 'pending',
      favorite: false,
      createdAt: DateTime(2026, 1, 1),
    );
    final repo = FakeItemRepository(initialItems: [pending]);
    // Nothing yet — the AI pipeline hasn't reached the tagging step.

    await tester.pumpWidget(wrap(pending, repo: repo));
    await tester.pumpAndSettle();

    expect(find.text('docker'), findsNothing);

    // The backend finishes processing AND produces tags in the same
    // run — itemTagsProvider/itemEntitiesProvider fetched (and cached)
    // "no tags" back when this screen first opened; without invalidating
    // them on this transition they'd keep showing nothing indefinitely.
    repo.tagsByItemId['item-1'] = ['docker'];
    repo.updateItem(pending.copyWith(processingStatus: 'completed'));
    await tester.pumpAndSettle();

    expect(find.text('docker'), findsOneWidget);
  });

  testWidgets('a stand-in for an item not yet synced to this device degrades gracefully, no crash',
      (tester) async {
    // Nothing in the local cache for this id — e.g. an item search just
    // surfaced that hasn't reached this device's Drift cache yet.
    await tester.pumpWidget(wrap(trimmedStandIn(id: 'not-synced-yet'), repo: FakeItemRepository()));
    await tester.pumpAndSettle();

    // Keeps showing what it was given rather than a dead end — findById()
    // returning null must never crash or blank the screen.
    expect(find.text('Untitled from search'), findsOneWidget);
    expect(find.text('Dosyayı Aç'), findsNothing); // never had a real storagePath to show one for
  });

  group('duplicate banner', () {
    testWidgets('shows once the item is flagged, and "Görüntüle" opens the original',
        (tester) async {
      final original = Item(
        id: 'item-original',
        type: ItemType.pdf,
        title: 'Original report',
        processingStatus: 'completed',
        favorite: false,
        createdAt: DateTime(2026, 1, 1),
      );
      final copy = Item(
        id: 'item-1',
        type: ItemType.pdf,
        title: 'Copy report',
        processingStatus: 'completed',
        favorite: false,
        createdAt: DateTime(2026, 1, 1),
        duplicateOfItemId: 'item-original',
        duplicateSimilarity: 1.0,
      );
      final repo = FakeItemRepository(initialItems: [original, copy]);

      final router = GoRouter(routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => ProviderScope(
            overrides: [
              itemRepositoryProvider.overrideWithValue(repo),
              searchRepositoryProvider.overrideWithValue(FakeSearchRepository()),
            ],
            child: ItemDetailScreen(item: copy),
          ),
        ),
        GoRoute(path: '/item/:id', builder: (context, state) => const Scaffold(body: Text('original screen'))),
      ]);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      expect(find.textContaining('zaten eklenmiş'), findsOneWidget);
      expect(find.text('Original report'), findsOneWidget);

      await tester.tap(find.text('Görüntüle'));
      await tester.pumpAndSettle();

      expect(find.text('original screen'), findsOneWidget);
    });

    testWidgets('"Yoksay" dismisses the banner for good', (tester) async {
      final original = Item(
        id: 'item-original',
        type: ItemType.pdf,
        title: 'Original report',
        processingStatus: 'completed',
        favorite: false,
        createdAt: DateTime(2026, 1, 1),
      );
      final copy = Item(
        id: 'item-1',
        type: ItemType.pdf,
        title: 'Copy report',
        processingStatus: 'completed',
        favorite: false,
        createdAt: DateTime(2026, 1, 1),
        duplicateOfItemId: 'item-original',
        duplicateSimilarity: 1.0,
      );
      final repo = FakeItemRepository(initialItems: [original, copy]);

      await tester.pumpWidget(wrap(copy, repo: repo));
      await tester.pumpAndSettle();

      expect(find.textContaining('zaten eklenmiş'), findsOneWidget);

      await tester.tap(find.text('Yoksay'));
      await tester.pumpAndSettle();

      expect(find.textContaining('zaten eklenmiş'), findsNothing);
    });
  });

  // P1-02 (docs/requirements-audit-2026-09-13.md): this screen used to
  // keep showing whatever item it was first given regardless of reveal
  // changing later — the one private-item entry point that didn't
  // re-hide live the way Home/Library/Search/collection detail already
  // did (e.g. `AppLockGate` resetting reveal when the app is
  // backgrounded while this exact screen is still on screen).
  group('re-locks when reveal turns off (P1-02)', () {
    testWidgets('an item that was already private when opened locks itself once reveal turns off',
        (tester) async {
      final item = Item(
        id: 'item-1',
        type: ItemType.note,
        title: 'Secret',
        processingStatus: 'completed',
        favorite: false,
        createdAt: DateTime(2026, 1, 1),
        private: true,
      );
      await tester.pumpWidget(wrap(
        item,
        repo: FakeItemRepository(initialItems: [item]),
        extraOverrides: [privateItemsRevealedProvider.overrideWith((ref) => true)],
      ));
      await tester.pumpAndSettle();

      expect(find.text('Secret'), findsOneWidget);
      expect(find.text('Kilidi Aç'), findsNothing);

      final container = ProviderScope.containerOf(tester.element(find.byType(ItemDetailScreen)));
      container.read(privateItemsRevealedProvider.notifier).state = false;
      await tester.pump();

      expect(find.text('Secret'), findsNothing);
      expect(find.text('Kilidi Aç'), findsOneWidget);
    });

    testWidgets('marking the currently-open item private yourself does not lock the screen',
        (tester) async {
      // Regression guard for the existing "no auth needed either way"
      // contract above: `_requiresRevealToView` is fixed at the item this
      // screen *opened* with, not whatever `_item.private` becomes after
      // the user's own toggle.
      final item = Item(
        id: 'item-1',
        type: ItemType.note,
        title: 'A note',
        processingStatus: 'completed',
        favorite: false,
        createdAt: DateTime(2026, 1, 1),
      );
      await tester.pumpWidget(wrap(item, repo: FakeItemRepository(initialItems: [item])));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.lock_open_outlined));
      await tester.pumpAndSettle();

      expect(find.text('A note'), findsOneWidget);
      expect(find.text('Kilidi Aç'), findsNothing);
    });

    testWidgets('tapping "Kilidi Aç" re-authenticates and reveals the screen again',
        (tester) async {
      final item = Item(
        id: 'item-1',
        type: ItemType.note,
        title: 'Secret',
        processingStatus: 'completed',
        favorite: false,
        createdAt: DateTime(2026, 1, 1),
        private: true,
      );
      final appLock = FakeAppLockService(authenticateResult: true);
      await tester.pumpWidget(wrap(
        item,
        repo: FakeItemRepository(initialItems: [item]),
        extraOverrides: [appLockServiceProvider.overrideWithValue(appLock)],
      ));
      await tester.pumpAndSettle();

      expect(find.text('Kilidi Aç'), findsOneWidget);

      await tester.tap(find.text('Kilidi Aç'));
      await tester.pumpAndSettle();

      expect(appLock.authenticateCallCount, 1);
      expect(find.text('Secret'), findsOneWidget);
      expect(find.text('Kilidi Aç'), findsNothing);
    });
  });
}
