import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesearch/features/collections/domain/entities/collection_suggestion.dart';
import 'package:lifesearch/features/collections/presentation/providers/collection_providers.dart';
import 'package:lifesearch/features/collections/presentation/providers/collection_suggestion_providers.dart';
import 'package:lifesearch/features/collections/presentation/widgets/collection_suggestions_section.dart';
import 'package:lifesearch/features/item/domain/entities/item.dart';

import '../fakes/fake_collection_repository.dart';
import '../fakes/fake_collection_suggestion_repository.dart';

void main() {
  final suggestion = const CollectionSuggestion(
    suggestedName: 'Docker Notları',
    items: [
      SuggestedItem(itemId: 'a', title: 'Docker Notes', itemType: ItemType.note),
      SuggestedItem(itemId: 'b', title: 'Docker Compose', itemType: ItemType.pdf),
      SuggestedItem(itemId: 'c', title: 'Docker Screenshot', itemType: ItemType.screenshot),
    ],
  );

  Widget wrap({
    FakeCollectionSuggestionRepository? suggestions,
    FakeCollectionRepository? collections,
  }) {
    return ProviderScope(
      overrides: [
        collectionSuggestionRepositoryProvider.overrideWithValue(
          suggestions ?? FakeCollectionSuggestionRepository(suggestions: [suggestion]),
        ),
        collectionRepositoryProvider.overrideWithValue(collections ?? FakeCollectionRepository()),
      ],
      child: const MaterialApp(home: Scaffold(body: CollectionSuggestionsSection())),
    );
  }

  testWidgets('renders nothing when there are no suggestions', (tester) async {
    await tester.pumpWidget(wrap(suggestions: FakeCollectionSuggestionRepository()));
    await tester.pumpAndSettle();

    expect(find.text('Önerilen Koleksiyonlar'), findsNothing);
  });

  testWidgets('shows a suggestion with its items', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.text('Docker Notları'), findsOneWidget);
    expect(find.text('Docker Notes'), findsOneWidget);
    expect(find.text('Docker Compose'), findsOneWidget);
  });

  testWidgets('"Yoksay" hides the suggestion', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Yoksay'));
    await tester.pumpAndSettle();

    expect(find.text('Docker Notları'), findsNothing);
  });

  testWidgets('"Oluştur" creates a smart collection with every suggested item', (tester) async {
    final collections = FakeCollectionRepository();
    await tester.pumpWidget(wrap(collections: collections));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Oluştur'));
    await tester.pumpAndSettle();

    expect(collections.createdSmartCollections, hasLength(1));
    final (name, memberIds) = collections.createdSmartCollections.single;
    expect(name, 'Docker Notları');
    expect(memberIds, {'a', 'b', 'c'});
    // Accepting also dismisses it — it's a real collection now.
    expect(find.text('Docker Notları'), findsNothing);
  });
}
