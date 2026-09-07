import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lifesearch/features/collections/presentation/providers/collection_providers.dart';
import 'package:lifesearch/features/collections/presentation/providers/collection_suggestion_providers.dart';
import 'package:lifesearch/features/item/domain/entities/item.dart';
import 'package:lifesearch/features/item/presentation/providers/item_providers.dart';
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
}
