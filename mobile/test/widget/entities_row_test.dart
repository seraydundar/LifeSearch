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
