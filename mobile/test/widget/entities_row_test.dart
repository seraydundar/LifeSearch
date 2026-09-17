import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lifesearch/features/item/domain/entities/extracted_entity.dart';
import 'package:lifesearch/features/item/presentation/providers/item_providers.dart';
import 'package:lifesearch/features/item/presentation/widgets/entities_row.dart';

import '../fakes/fake_item_repository.dart';

void main() {
  Widget wrap(FakeItemRepository repo) {
    return ProviderScope(
      overrides: [itemRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp.router(
        routerConfig: GoRouter(routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const Scaffold(body: EntitiesRow(itemId: 'item-1')),
          ),
          GoRoute(
            path: '/search',
            builder: (context, state) => Scaffold(body: Text('search: ${state.extra}')),
          ),
        ]),
      ),
    );
  }

  testWidgets('renders nothing when the item has no entities', (tester) async {
    await tester.pumpWidget(wrap(FakeItemRepository()));
    await tester.pumpAndSettle();

    expect(find.byType(ActionChip), findsNothing);
  });

  testWidgets('shows a chip per entity, with a type-specific icon', (tester) async {
    final repo = FakeItemRepository()
      ..entitiesByItemId['item-1'] = const [
        ExtractedEntity(name: 'Ahmet Yılmaz', type: EntityType.person),
        ExtractedEntity(name: 'İstanbul', type: EntityType.place),
      ];
    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    expect(find.text('Ahmet Yılmaz'), findsOneWidget);
    expect(find.text('İstanbul'), findsOneWidget);
    expect(find.byIcon(Icons.person_outline), findsOneWidget);
    expect(find.byIcon(Icons.place_outlined), findsOneWidget);
  });

  // P3 (docs/requirements-audit-2026-09-13.md): product/price/website/
  // technology added to the original person/place/organization/date set.
  testWidgets('shows a chip with a type-specific icon for each newly added type',
      (tester) async {
    final repo = FakeItemRepository()
      ..entitiesByItemId['item-1'] = const [
        ExtractedEntity(name: 'iPhone 17 Pro', type: EntityType.product),
        ExtractedEntity(name: '1200 TL', type: EntityType.price),
        ExtractedEntity(name: 'github.com', type: EntityType.website),
        ExtractedEntity(name: 'Flutter', type: EntityType.technology),
      ];
    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    expect(find.text('iPhone 17 Pro'), findsOneWidget);
    expect(find.text('1200 TL'), findsOneWidget);
    expect(find.text('github.com'), findsOneWidget);
    expect(find.text('Flutter'), findsOneWidget);
    expect(find.byIcon(Icons.shopping_bag_outlined), findsOneWidget);
    expect(find.byIcon(Icons.sell_outlined), findsOneWidget);
    expect(find.byIcon(Icons.link_outlined), findsOneWidget);
    expect(find.byIcon(Icons.memory_outlined), findsOneWidget);
  });

  testWidgets('tapping an entity opens search with its name as the query', (tester) async {
    final repo = FakeItemRepository()
      ..entitiesByItemId['item-1'] = const [
        ExtractedEntity(name: 'Ahmet Yılmaz', type: EntityType.person),
      ];
    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ahmet Yılmaz'));
    await tester.pumpAndSettle();

    expect(find.text('search: Ahmet Yılmaz'), findsOneWidget);
  });
}
