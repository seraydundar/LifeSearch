import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lifesearch/features/item/domain/entities/item.dart';
import 'package:lifesearch/features/item/presentation/providers/item_providers.dart';
import 'package:lifesearch/features/library/presentation/widgets/item_grid_tile.dart';

import '../fakes/fake_item_repository.dart';

void main() {
  Widget wrap(Item item, {FakeItemRepository? repo}) {
    return ProviderScope(
      overrides: [itemRepositoryProvider.overrideWithValue(repo ?? FakeItemRepository())],
      child: MaterialApp.router(
        routerConfig: GoRouter(routes: [
          GoRoute(path: '/', builder: (context, state) => Scaffold(body: ItemGridTile(item: item))),
          GoRoute(
            path: '/item/:id',
            builder: (context, state) => const Scaffold(body: Text('detail')),
          ),
          GoRoute(
            path: '/item/:id/note',
            builder: (context, state) => const Scaffold(body: Text('note editor')),
          ),
        ]),
      ),
    );
  }

  testWidgets('a non-image item shows its type icon and title, no network fetch', (tester) async {
    await tester.pumpWidget(wrap(Item(
      id: '1',
      type: ItemType.note,
      title: 'Docker Notes',
      processingStatus: 'completed',
      favorite: false,
      createdAt: DateTime(2026, 1, 1),
    )));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.notes_outlined), findsOneWidget);
    expect(find.text('Docker Notes'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('an image item whose signed URL fails to load shows the fallback icon',
      (tester) async {
    // flutter_test fakes every HTTP request as a 400 — Image.network's
    // errorBuilder is exactly what this exercises: a signed URL that
    // expired or a network blip shouldn't leave a broken-image icon.
    await tester.pumpWidget(wrap(Item(
      id: '1',
      type: ItemType.image,
      originalFilename: 'sunset.jpg',
      storagePath: 'user/1/sunset.jpg',
      processingStatus: 'completed',
      favorite: false,
      createdAt: DateTime(2026, 1, 1),
    )));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
  });

  testWidgets('a favorited item shows the star badge', (tester) async {
    await tester.pumpWidget(wrap(Item(
      id: '1',
      type: ItemType.note,
      title: 'Starred',
      processingStatus: 'completed',
      favorite: true,
      createdAt: DateTime(2026, 1, 1),
    )));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.star), findsOneWidget);
  });

  testWidgets('tapping navigates to the item detail route', (tester) async {
    await tester.pumpWidget(wrap(Item(
      id: '42',
      type: ItemType.pdf,
      title: 'Report',
      processingStatus: 'completed',
      favorite: false,
      createdAt: DateTime(2026, 1, 1),
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();

    expect(find.text('detail'), findsOneWidget);
  });

  testWidgets('tapping a note navigates to the note editor route', (tester) async {
    await tester.pumpWidget(wrap(Item(
      id: '7',
      type: ItemType.note,
      title: 'My note',
      processingStatus: 'completed',
      favorite: false,
      createdAt: DateTime(2026, 1, 1),
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('My note'));
    await tester.pumpAndSettle();

    expect(find.text('note editor'), findsOneWidget);
  });
}
