import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lifesearch/features/collections/domain/entities/collection.dart';
import 'package:lifesearch/features/collections/presentation/providers/collection_providers.dart';
import 'package:lifesearch/features/collections/presentation/widgets/collections_bar.dart';

import '../fakes/fake_collection_repository.dart';

void main() {
  Widget wrap(FakeCollectionRepository repo, {String? pushedTo}) {
    return ProviderScope(
      overrides: [collectionRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp.router(
        routerConfig: GoRouter(routes: [
          GoRoute(path: '/', builder: (context, state) => const Scaffold(body: CollectionsBar())),
          GoRoute(
            path: '/collections/:id',
            builder: (context, state) => const Scaffold(body: Text('collection detail')),
          ),
        ]),
      ),
    );
  }

  testWidgets('always shows the "new collection" chip, plus one per existing collection',
      (tester) async {
    final repo = FakeCollectionRepository(initialCollections: [
      Collection(id: 'c1', name: 'Docker', isSmart: false, createdAt: DateTime(2026, 1, 1)),
    ]);
    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    expect(find.text('Yeni Koleksiyon'), findsOneWidget);
    expect(find.text('Docker'), findsOneWidget);
  });

  testWidgets('tapping a collection chip navigates to its detail screen', (tester) async {
    final repo = FakeCollectionRepository(initialCollections: [
      Collection(id: 'c1', name: 'Docker', isSmart: false, createdAt: DateTime(2026, 1, 1)),
    ]);
    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Docker'));
    await tester.pumpAndSettle();

    expect(find.text('collection detail'), findsOneWidget);
  });
}
