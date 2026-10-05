import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lifesearch/features/collections/domain/entities/collection.dart';
import 'package:lifesearch/features/collections/presentation/providers/collection_providers.dart';
import 'package:lifesearch/features/collections/presentation/screens/collection_detail_screen.dart';
import 'package:lifesearch/features/item/domain/entities/item.dart';

import '../fakes/fake_collection_repository.dart';

void main() {
  Widget wrap(FakeCollectionRepository repo) {
    return ProviderScope(
      overrides: [collectionRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp.router(
        routerConfig: GoRouter(routes: [
          GoRoute(
            path: '/',
            builder: (context, state) =>
                const CollectionDetailScreen(collectionId: 'c1', name: 'Docker'),
          ),
          GoRoute(path: '/item/:id', builder: (context, state) => const Scaffold(body: Text('detail'))),
        ]),
      ),
    );
  }

  testWidgets('shows an empty state when the collection has no items', (tester) async {
    await tester.pumpWidget(wrap(FakeCollectionRepository()));
    await tester.pumpAndSettle();

    expect(find.textContaining('Bu koleksiyon henüz boş'), findsOneWidget);
  });

  testWidgets('lists the collection\'s items', (tester) async {
    final repo = FakeCollectionRepository();
    repo.itemsByCollection['c1'] = [
      Item(
        id: 'item-1',
        type: ItemType.note,
        title: 'Docker Notes',
        processingStatus: 'completed',
        favorite: false,
        createdAt: DateTime(2026, 1, 1),
      ),
    ];
    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    expect(find.text('Docker Notes'), findsOneWidget);
  });

  // The AppBar title used to be the `name` passed in at navigation time —
  // a rename while this screen stayed open never showed until leaving and
  // coming back, since nothing re-read the collection's current name.
  testWidgets('renaming updates the title immediately, without leaving the screen',
      (tester) async {
    final repo = FakeCollectionRepository(
      initialCollections: [
        Collection(id: 'c1', name: 'Docker', isSmart: false, createdAt: DateTime(2026, 1, 1)),
      ],
    );
    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    expect(find.text('Docker'), findsOneWidget);

    await tester.tap(find.byTooltip('Yeniden adlandır'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Docker Notları');
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();

    expect(find.text('Docker Notları'), findsOneWidget);
    expect(find.text('Docker'), findsNothing);
  });
}
