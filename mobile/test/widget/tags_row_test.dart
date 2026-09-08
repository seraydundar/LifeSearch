import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lifesearch/features/item/presentation/providers/item_providers.dart';
import 'package:lifesearch/features/item/presentation/widgets/tags_row.dart';

import '../fakes/fake_item_repository.dart';

void main() {
  Widget wrap(FakeItemRepository repo) {
    return ProviderScope(
      overrides: [itemRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp.router(
        routerConfig: GoRouter(routes: [
          GoRoute(path: '/', builder: (context, state) => const Scaffold(body: TagsRow(itemId: 'item-1'))),
          GoRoute(
            path: '/search',
            builder: (context, state) => Scaffold(body: Text('search: ${state.extra}')),
          ),
        ]),
      ),
    );
  }

  testWidgets('renders nothing when the item has no tags', (tester) async {
    await tester.pumpWidget(wrap(FakeItemRepository()));
    await tester.pumpAndSettle();

    expect(find.byType(ActionChip), findsNothing);
  });

  testWidgets('shows a chip per tag', (tester) async {
    final repo = FakeItemRepository()..tagsByItemId['item-1'] = ['docker', 'devops'];
    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    expect(find.text('docker'), findsOneWidget);
    expect(find.text('devops'), findsOneWidget);
  });

  testWidgets('tapping a tag opens search with it as the query', (tester) async {
    final repo = FakeItemRepository()..tagsByItemId['item-1'] = ['docker'];
    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('docker'));
    await tester.pumpAndSettle();

    expect(find.text('search: docker'), findsOneWidget);
  });
}
