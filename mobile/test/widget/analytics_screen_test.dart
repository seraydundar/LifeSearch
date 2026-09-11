import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesearch/features/analytics/presentation/screens/analytics_screen.dart';
import 'package:lifesearch/features/item/domain/entities/item.dart';
import 'package:lifesearch/features/item/presentation/providers/item_providers.dart';

import '../fakes/fake_item_repository.dart';

void main() {
  Widget wrap(FakeItemRepository repo, {bool privateRevealed = false}) {
    return ProviderScope(
      // Always the same *number* of overrides across every call — a
      // second `pumpWidget()` with a different override count on the
      // same ProviderScope element throws ("Tried to change the number
      // of overrides"), so the reveal test below toggles this value,
      // never whether the override itself is present.
      overrides: [
        itemRepositoryProvider.overrideWithValue(repo),
        privateItemsRevealedProvider.overrideWith((ref) => privateRevealed),
      ],
      child: const MaterialApp(home: AnalyticsScreen()),
    );
  }

  Item item({
    required String id,
    ItemType type = ItemType.note,
    bool favorite = false,
    bool private = false,
    int? fileSizeBytes,
    required DateTime createdAt,
  }) {
    return Item(
      id: id,
      type: type,
      processingStatus: 'completed',
      favorite: favorite,
      private: private,
      createdAt: createdAt,
      fileSizeBytes: fileSizeBytes,
    );
  }

  testWidgets('an empty archive shows zeroed stats and no type breakdown', (tester) async {
    await tester.pumpWidget(wrap(FakeItemRepository()));
    await tester.pumpAndSettle();

    expect(find.text('0'), findsWidgets); // Toplam / Favori
    expect(find.text('Henüz içerik yok.'), findsOneWidget);
  });

  testWidgets('shows total/favorite counts and a bar per type present', (tester) async {
    final repo = FakeItemRepository(initialItems: [
      item(id: '1', type: ItemType.note, favorite: true, createdAt: DateTime(2026, 1, 1)),
      item(id: '2', type: ItemType.note, createdAt: DateTime(2026, 1, 2)),
      item(id: '3', type: ItemType.pdf, createdAt: DateTime(2026, 1, 3)),
    ]);
    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    expect(find.text('3'), findsOneWidget); // Toplam
    expect(find.text('1'), findsWidgets); // Favori + PDF's own bar count
    expect(find.text('Not'), findsOneWidget); // note's own label, from itemTypeLabel
    expect(find.text('PDF'), findsOneWidget);
    // Never rendered for a type with nothing in it.
    expect(find.text('Ses'), findsNothing);
  });

  List<Item> archiveWithOnePrivateItem() => [
        item(id: '1', type: ItemType.note, createdAt: DateTime(2026, 1, 1)),
        item(id: '2', type: ItemType.pdf, private: true, createdAt: DateTime(2026, 1, 1)),
      ];

  testWidgets('a private item never counts toward any stat by default', (tester) async {
    final repo = FakeItemRepository(initialItems: archiveWithOnePrivateItem());

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    // "1" shows up on purpose here — the Toplam stat and the visible
    // note's own bar count both read 1 — so this checks the things that
    // unambiguously prove the private item doesn't count: its own type
    // never appears, and no tile even hints a private item exists.
    expect(find.text('PDF'), findsNothing);
    expect(find.textContaining('Private'), findsNothing);
  });

  testWidgets('revealing private items folds it into every stat', (tester) async {
    final repo = FakeItemRepository(initialItems: archiveWithOnePrivateItem());

    await tester.pumpWidget(wrap(repo, privateRevealed: true));
    await tester.pumpAndSettle();

    expect(find.text('2'), findsOneWidget); // Toplam now counts both
    expect(find.text('PDF'), findsOneWidget);
    expect(find.text('Private'), findsOneWidget); // the stat tile itself
    expect(find.text('1'), findsWidgets); // the Private stat's own value
  });

  testWidgets('shows the most common tags, most-frequent first', (tester) async {
    final repo = FakeItemRepository(initialItems: [
      item(id: '1', createdAt: DateTime(2026, 1, 1)),
    ]);
    repo.allTagNames = ['docker', 'kubernetes', 'docker'];

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    expect(find.text('docker · 2'), findsOneWidget);
    expect(find.text('kubernetes · 1'), findsOneWidget);
  });

  testWidgets('no tags yet shows a plain message, not an empty gap', (tester) async {
    final repo = FakeItemRepository(initialItems: [
      item(id: '1', createdAt: DateTime(2026, 1, 1)),
    ]);

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    expect(find.text('Henüz etiket yok.'), findsOneWidget);
  });
}
