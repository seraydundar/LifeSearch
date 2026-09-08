import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lifesearch/features/collections/presentation/providers/collection_providers.dart';
import 'package:lifesearch/features/collections/presentation/providers/collection_suggestion_providers.dart';
import 'package:lifesearch/features/item/domain/entities/item.dart';
import 'package:lifesearch/features/item/presentation/providers/item_providers.dart';
import 'package:lifesearch/features/item/presentation/widgets/item_list_tile.dart';
import 'package:lifesearch/features/library/presentation/screens/library_screen.dart';

import '../fakes/fake_collection_repository.dart';
import '../fakes/fake_collection_suggestion_repository.dart';
import '../fakes/fake_item_repository.dart';

void main() {
  Widget wrap(FakeItemRepository repo, {FakeCollectionRepository? collections}) {
    return ProviderScope(
      overrides: [
        itemRepositoryProvider.overrideWithValue(repo),
        collectionRepositoryProvider.overrideWithValue(collections ?? FakeCollectionRepository()),
        collectionSuggestionRepositoryProvider
            .overrideWithValue(FakeCollectionSuggestionRepository()),
      ],
      child: MaterialApp.router(
        routerConfig: GoRouter(routes: [
          GoRoute(path: '/', builder: (context, state) => const LibraryScreen()),
          GoRoute(path: '/item/:id', builder: (context, state) => const Scaffold(body: Text('detail'))),
          GoRoute(
            path: '/item/:id/note',
            builder: (context, state) => const Scaffold(body: Text('note editor')),
          ),
        ]),
      ),
    );
  }

  testWidgets('shows an empty state when there are no items', (tester) async {
    await tester.pumpWidget(wrap(FakeItemRepository()));
    await tester.pumpAndSettle();

    expect(find.text('Kütüphanen boş. + ile ilk içeriğini ekle.'), findsOneWidget);
  });

  testWidgets('lists items and navigates to note editor on tap', (tester) async {
    final repo = FakeItemRepository(initialItems: [
      Item(
        id: '1',
        type: ItemType.note,
        title: 'Docker Notes',
        processingStatus: 'completed',
        favorite: false,
        createdAt: DateTime(2026, 1, 1),
      ),
    ]);
    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    expect(find.text('Docker Notes'), findsOneWidget);

    await tester.tap(find.text('Docker Notes'));
    await tester.pumpAndSettle();

    expect(find.text('note editor'), findsOneWidget);
  });

  testWidgets('favorites filter hides non-favorited items', (tester) async {
    final repo = FakeItemRepository(initialItems: [
      Item(
        id: '1',
        type: ItemType.note,
        title: 'Not favorited',
        processingStatus: 'completed',
        favorite: false,
        createdAt: DateTime(2026, 1, 1),
      ),
    ]);
    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();
    expect(find.text('Not favorited'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.star_border));
    await tester.pumpAndSettle();

    expect(find.text('Not favorited'), findsNothing);
    expect(find.text('Henüz favori işaretlediğin bir şey yok.'), findsOneWidget);
  });

  testWidgets('starts in list view and switches to a grid on tap', (tester) async {
    final repo = FakeItemRepository(initialItems: [
      Item(
        id: '1',
        type: ItemType.note,
        title: 'Docker Notes',
        processingStatus: 'completed',
        favorite: false,
        createdAt: DateTime(2026, 1, 1),
      ),
    ]);
    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    expect(find.byType(ItemListTile), findsOneWidget);
    expect(find.byType(GridView), findsNothing);

    await tester.tap(find.byIcon(Icons.grid_view_outlined));
    await tester.pumpAndSettle();

    expect(find.byType(GridView), findsOneWidget);
    expect(find.byType(ItemListTile), findsNothing);
    expect(find.text('Docker Notes'), findsOneWidget);
  });

  testWidgets('sorting reorders the list', (tester) async {
    // "Banana notes" is newer but alphabetically after "Apple notes" — the
    // three sort modes below each put a different one first, so a passing
    // test proves the sort actually took effect rather than coincidentally
    // matching the default order.
    final repo = FakeItemRepository(initialItems: [
      Item(
        id: '1',
        type: ItemType.note,
        title: 'Banana notes',
        processingStatus: 'completed',
        favorite: false,
        createdAt: DateTime(2026, 1, 2),
      ),
      Item(
        id: '2',
        type: ItemType.note,
        title: 'Apple notes',
        processingStatus: 'completed',
        favorite: false,
        createdAt: DateTime(2026, 1, 1),
      ),
    ]);
    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    List<String> renderedTitles() => tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .toList();

    // Default: newest first — "Banana notes" (Jan 2) before "Apple notes"
    // (Jan 1).
    var titles = renderedTitles();
    expect(titles.indexOf('Banana notes'), lessThan(titles.indexOf('Apple notes')));

    await tester.tap(find.byIcon(Icons.sort));
    await tester.pumpAndSettle();
    await tester.tap(find.text('İsme göre (A-Z)'));
    await tester.pumpAndSettle();

    titles = renderedTitles();
    expect(titles.indexOf('Apple notes'), lessThan(titles.indexOf('Banana notes')));

    await tester.tap(find.byIcon(Icons.sort));
    await tester.pumpAndSettle();
    await tester.tap(find.text('En eski'));
    await tester.pumpAndSettle();

    titles = renderedTitles();
    expect(titles.indexOf('Apple notes'), lessThan(titles.indexOf('Banana notes')));
  });
}
