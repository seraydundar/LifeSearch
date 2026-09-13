import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesearch/features/item/domain/entities/item.dart';
import 'package:lifesearch/features/item/presentation/providers/item_providers.dart';
import 'package:lifesearch/shared/widgets/item_by_id_loader.dart';

import '../fakes/fake_item_repository.dart';

void main() {
  final item = Item(
    id: 'item-1',
    type: ItemType.note,
    title: 'Docker Notes',
    processingStatus: 'completed',
    favorite: false,
    createdAt: DateTime(2026, 1, 1),
  );

  Widget wrap(
    FakeItemRepository repo, {
    String itemId = 'item-1',
    List<Override> extraOverrides = const [],
  }) {
    return ProviderScope(
      overrides: [
        itemRepositoryProvider.overrideWithValue(repo),
        ...extraOverrides,
      ],
      child: MaterialApp(
        home: ItemByIdLoader(
          itemId: itemId,
          builder: (resolved) => Scaffold(body: Text('resolved: ${resolved.title}')),
        ),
      ),
    );
  }

  testWidgets('shows a spinner while the item is being resolved', (tester) async {
    await tester.pumpWidget(wrap(FakeItemRepository(initialItems: [item])));

    // Before the first pump settles, findById's Future hasn't completed yet.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('hands the resolved item to builder once found', (tester) async {
    await tester.pumpWidget(wrap(FakeItemRepository(initialItems: [item])));
    await tester.pumpAndSettle();

    expect(find.text('resolved: Docker Notes'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('shows a not-found state instead of crashing when the id is unknown',
      (tester) async {
    // Empty repo — this is the case a crash-on-cast used to hit: a route
    // reached without an `extra` Item, for an id the local cache has
    // never seen (a cold deep link before the first sync).
    await tester.pumpWidget(wrap(FakeItemRepository(), itemId: 'never-synced'));
    await tester.pumpAndSettle();

    expect(find.textContaining('bulunamadı'), findsOneWidget);
    expect(find.text('resolved: Docker Notes'), findsNothing);
  });

  // P1-02 (docs/requirements-audit-2026-09-13.md): this was a second,
  // unguarded way to reach a private item's detail screen — a deep link,
  // push notification, or Android/iOS route restore skips every other
  // private filter (Home/Library/Search all gate on `itemsProvider`'s tap
  // targets, which this never goes through).
  testWidgets('a private item does not resolve while reveal is off', (tester) async {
    final privateItem = item.copyWith(private: true);
    await tester.pumpWidget(wrap(FakeItemRepository(initialItems: [privateItem])));
    await tester.pumpAndSettle();

    expect(find.textContaining('bulunamadı'), findsOneWidget);
    expect(find.text('resolved: Docker Notes'), findsNothing);
  });

  testWidgets('a private item resolves once reveal is on', (tester) async {
    final privateItem = item.copyWith(private: true);
    await tester.pumpWidget(wrap(
      FakeItemRepository(initialItems: [privateItem]),
      extraOverrides: [privateItemsRevealedProvider.overrideWith((ref) => true)],
    ));
    await tester.pumpAndSettle();

    expect(find.text('resolved: Docker Notes'), findsOneWidget);
  });
}
