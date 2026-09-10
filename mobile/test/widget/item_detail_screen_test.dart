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
