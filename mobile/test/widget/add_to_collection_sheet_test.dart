import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesearch/features/collections/domain/entities/collection.dart';
import 'package:lifesearch/features/collections/presentation/providers/collection_providers.dart';
import 'package:lifesearch/features/collections/presentation/widgets/add_to_collection_sheet.dart';

import '../fakes/fake_collection_repository.dart';

void main() {
  Widget wrap(FakeCollectionRepository repo) {
    return ProviderScope(
      overrides: [collectionRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(
        home: Scaffold(body: AddToCollectionSheet(itemId: 'item-1')),
      ),
    );
  }

  // Found live: with no collections yet, the sheet's content (a one-line
  // "Henüz koleksiyonun yok." message) was all `showModalBottomSheet` had
  // to size around, so it shrank narrower than once a collection existed
  // — a visibly inconsistent sheet width depending on data.
  testWidgets('stays full width with no collections yet', (tester) async {
    await tester.pumpWidget(wrap(FakeCollectionRepository()));
    await tester.pumpAndSettle();

    expect(find.text('Henüz koleksiyonun yok.'), findsOneWidget);
    final sheetWidth = tester.getSize(find.byType(AddToCollectionSheet)).width;
    final scaffoldWidth = tester.getSize(find.byType(Scaffold)).width;
    expect(sheetWidth, scaffoldWidth);
  });

  testWidgets('stays the same full width once a collection exists', (tester) async {
    final repo = FakeCollectionRepository(
      initialCollections: [
        Collection(id: 'c1', name: 'Docker', isSmart: false, createdAt: DateTime(2026, 1, 1)),
      ],
    );
    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    expect(find.text('Docker'), findsOneWidget);
    final sheetWidth = tester.getSize(find.byType(AddToCollectionSheet)).width;
    final scaffoldWidth = tester.getSize(find.byType(Scaffold)).width;
    expect(sheetWidth, scaffoldWidth);
  });
}
