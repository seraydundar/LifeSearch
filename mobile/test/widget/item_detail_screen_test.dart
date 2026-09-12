import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesearch/features/item/domain/entities/item.dart';
import 'package:lifesearch/features/item/presentation/providers/item_providers.dart';
import 'package:lifesearch/features/item/presentation/screens/item_detail_screen.dart';
import 'package:lifesearch/features/search/presentation/providers/search_providers.dart';

import '../fakes/fake_item_repository.dart';
import '../fakes/fake_search_repository.dart';

void main() {
  Widget wrap(Item openedWith, {FakeItemRepository? repo}) {
    return ProviderScope(
      overrides: [
        itemRepositoryProvider.overrideWithValue(repo ?? FakeItemRepository()),
        searchRepositoryProvider.overrideWithValue(FakeSearchRepository()),
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
}
