import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:lifesearch/core/database/app_database.dart';
import 'package:lifesearch/core/database/database_provider.dart';
import 'package:lifesearch/core/error/failure.dart';
import 'package:lifesearch/features/item/domain/entities/item.dart';
import 'package:lifesearch/features/item/presentation/providers/item_providers.dart';
import 'package:lifesearch/features/search/presentation/providers/search_providers.dart';
import 'package:lifesearch/features/search/presentation/screens/search_tab.dart';

import '../fakes/fake_item_repository.dart';
import '../fakes/fake_search_repository.dart';

void main() {
  // Each test below opens its own isolated in-memory database — Drift's
  // "constructed more than once" heuristic can't tell that apart from the
  // real footgun it's meant to catch, so it's just noise here.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  Widget wrap(
    FakeSearchRepository repo, {
    List<String> recent = const [],
    String? initialQuery,
    FakeItemRepository? itemRepo,
  }) {
    return ProviderScope(
      overrides: [
        searchRepositoryProvider.overrideWithValue(repo),
        recentSearchesProvider.overrideWith((ref) => Stream.value(recent)),
        // SearchController.search() records to recentSearchesDataSourceProvider
        // on success — give it an in-memory db instead of touching a real file.
        appDatabaseProvider.overrideWithValue(AppDatabase.forTesting(NativeDatabase.memory())),
        if (itemRepo != null) itemRepositoryProvider.overrideWithValue(itemRepo),
      ],
      child: MaterialApp(home: Scaffold(body: SearchTab(initialQuery: initialQuery))),
    );
  }

  testWidgets('shows a prompt when there is no query and no history', (tester) async {
    await tester.pumpWidget(wrap(FakeSearchRepository()));
    await tester.pumpAndSettle();

    expect(find.textContaining('Arşivinde doğal dille arama yap'), findsOneWidget);
  });

  testWidgets('shows recent searches when the query is empty', (tester) async {
    await tester.pumpWidget(wrap(FakeSearchRepository(), recent: ['Docker deployment']));
    await tester.pumpAndSettle();

    expect(find.text('Docker deployment'), findsOneWidget);
  });

  testWidgets('submitting a query shows matching results', (tester) async {
    final repo = FakeSearchRepository(resultsToReturn: [fakeSearchResult()]);
    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Docker notes');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(repo.lastQuery, 'Docker notes');
    expect(find.text('Docker Notes'), findsOneWidget);
    expect(find.textContaining('Docker container'), findsOneWidget);
  });

  testWidgets('shows an empty state when nothing matches', (tester) async {
    final repo = FakeSearchRepository(resultsToReturn: []);
    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'nonsense query');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.text('Sonuç bulunamadı.'), findsOneWidget);
  });

  testWidgets('shows the failure message when search errors out', (tester) async {
    final repo = FakeSearchRepository(
      errorToThrow: const UnexpectedFailure('Arama şu anda kullanılamıyor.'),
    );
    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Docker notes');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.text('Arama şu anda kullanılamıyor.'), findsOneWidget);
  });

  testWidgets("a private item's own result is hidden from search, others still show",
      (tester) async {
    // A `SearchResult` only carries an id/snippet — this checks it
    // against the local cache's `private` flag (Faz 11, madde 2 — see
    // docs/roadmap.md), so the corresponding Item has to exist there too.
    final privateItem = Item(
      id: 'item-1',
      type: ItemType.note,
      title: 'Secret note',
      processingStatus: 'completed',
      favorite: false,
      createdAt: DateTime(2026, 1, 1),
      private: true,
    );
    final publicItem = Item(
      id: 'item-2',
      type: ItemType.note,
      title: 'Public note',
      processingStatus: 'completed',
      favorite: false,
      createdAt: DateTime(2026, 1, 1),
    );
    final repo = FakeSearchRepository(resultsToReturn: [
      fakeSearchResult(itemId: 'item-1', itemTitle: 'Secret note'),
      fakeSearchResult(itemId: 'item-2', itemTitle: 'Public note'),
    ]);
    await tester.pumpWidget(wrap(
      repo,
      initialQuery: 'note',
      itemRepo: FakeItemRepository(initialItems: [privateItem, publicItem]),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Public note'), findsOneWidget);
    expect(find.text('Secret note'), findsNothing);
  });

  testWidgets('an initialQuery (e.g. a tapped tag) runs automatically', (tester) async {
    final repo = FakeSearchRepository(resultsToReturn: [fakeSearchResult()]);
    await tester.pumpWidget(wrap(repo, initialQuery: 'docker'));
    await tester.pumpAndSettle();

    expect(repo.lastQuery, 'docker');
    expect(find.text('Docker Notes'), findsOneWidget);
  });

  testWidgets('picking a custom date range applies both ends as filters', (tester) async {
    final repo = FakeSearchRepository(resultsToReturn: [fakeSearchResult()]);
    await tester.pumpWidget(wrap(repo, initialQuery: 'docker'));
    await tester.pumpAndSettle();

    // The date chip sits at the end of a horizontally-scrolling filter
    // row — off the default test viewport until scrolled into view.
    await tester.ensureVisible(find.text('Her zaman'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Her zaman')); // opens the date preset menu
    await tester.pumpAndSettle();
    await tester.tap(find.text('Özel aralık…'));
    await tester.pumpAndSettle();

    // The picker opens on the current month's calendar grid (no
    // `initialDateRange` yet) — picking the 1st and 5th of that month
    // directly is far less brittle across Flutter versions than typing
    // into the keyboard-entry mode's date fields.
    await tester.tap(find.text('1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('5'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final now = DateTime.now();
    final expectedFrom = DateTime(now.year, now.month, 1);
    final expectedTo = DateTime(now.year, now.month, 5, 23, 59, 59, 999, 999);
    expect(repo.lastFilters!.dateFrom, expectedFrom);
    expect(repo.lastFilters!.dateTo, expectedTo);
    final format = DateFormat('d MMM');
    expect(
      find.text('${format.format(expectedFrom)} - ${format.format(expectedTo)}'),
      findsOneWidget,
    );
  });

  testWidgets('cancelling the date range picker keeps the previous filter active',
      (tester) async {
    final repo = FakeSearchRepository(resultsToReturn: [fakeSearchResult()]);
    await tester.pumpWidget(wrap(repo, initialQuery: 'docker'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Her zaman'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Her zaman'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bugün')); // a real filter, not "Her zaman" itself
    await tester.pumpAndSettle();
    final filtersAfterToday = repo.lastFilters;

    await tester.ensureVisible(find.text('Bugün'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bugün'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Özel aralık…'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close)); // the picker's own dismiss button
    await tester.pumpAndSettle();

    // Neither the chip nor the last-applied filters changed — a
    // cancelled picker must never wipe out what was already selected.
    expect(find.text('Bugün'), findsOneWidget);
    expect(find.text('Özel aralık…'), findsNothing); // the menu itself closed
    expect(repo.lastFilters, filtersAfterToday);
  });
}
