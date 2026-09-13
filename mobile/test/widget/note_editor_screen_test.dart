import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lifesearch/features/item/domain/entities/item.dart';
import 'package:lifesearch/features/item/presentation/providers/item_providers.dart';
import 'package:lifesearch/features/item/presentation/screens/note_editor_screen.dart';

import '../fakes/fake_item_repository.dart';

void main() {
  // Faz 12, madde 12 (denetim düzeltmesi — see docs/roadmap.md): notes
  // go through the same AI pipeline (tagging/entities/embedding) and
  // support the same favorite/Private/delete actions every other item
  // type does, but this screen had none of the corresponding controls
  // — only "add to collection" and "save".
  Widget wrap(Item? openedWith, {FakeItemRepository? repo}) {
    return ProviderScope(
      overrides: [
        itemRepositoryProvider.overrideWithValue(repo ?? FakeItemRepository()),
      ],
      child: MaterialApp(home: NoteEditorScreen(item: openedWith)),
    );
  }

  Item note({
    String id = 'note-1',
    String title = 'A note',
    bool favorite = false,
    bool private = false,
    String processingStatus = 'completed',
  }) {
    return Item(
      id: id,
      type: ItemType.note,
      title: title,
      processingStatus: processingStatus,
      favorite: favorite,
      private: private,
      createdAt: DateTime(2026, 1, 1),
    );
  }

  group('create mode (no item)', () {
    testWidgets('shows none of the item-specific actions — nothing to act on yet',
        (tester) async {
      await tester.pumpWidget(wrap(null));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.star_border), findsNothing);
      expect(find.byIcon(Icons.lock_open_outlined), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
      expect(find.byIcon(Icons.folder_outlined), findsNothing);
    });
  });

  group('edit mode', () {
    testWidgets('the favorite toggle marks and unmarks the note', (tester) async {
      final item = note();
      final repo = FakeItemRepository(initialItems: [item]);

      await tester.pumpWidget(wrap(item, repo: repo));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.star_border), findsOneWidget);

      await tester.tap(find.byIcon(Icons.star_border));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.star), findsOneWidget);
      expect((await repo.findById('note-1'))!.favorite, isTrue);
    });

    testWidgets('the private toggle marks and unmarks the note', (tester) async {
      final item = note();
      final repo = FakeItemRepository(initialItems: [item]);

      await tester.pumpWidget(wrap(item, repo: repo));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.lock_open_outlined), findsOneWidget);

      await tester.tap(find.byIcon(Icons.lock_open_outlined));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect((await repo.findById('note-1'))!.private, isTrue);
    });

    testWidgets('deleting asks for confirmation, then pops on success', (tester) async {
      final item = note();
      final repo = FakeItemRepository(initialItems: [item]);

      // The confirm dialog's buttons use go_router's `context.pop()`
      // (consistent with the rest of the app's confirm dialogs, e.g.
      // Settings' Delete Account), which needs a real GoRouter ancestor
      // — a plain `MaterialApp(home:)`/`Navigator.push` doesn't have
      // one (found live: this exact test threw "No GoRouter found in
      // context" before being switched to `MaterialApp.router`).
      final router = GoRouter(routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => context.push('/note'),
              child: const Text('open'),
            ),
          ),
        ),
        GoRoute(path: '/note', builder: (context, state) => NoteEditorScreen(item: item)),
      ]);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [itemRepositoryProvider.overrideWithValue(repo)],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      expect(find.text('Bu işlem geri alınamaz.'), findsOneWidget);

      await tester.tap(find.text('Sil'));
      await tester.pumpAndSettle();

      expect(find.byType(NoteEditorScreen), findsNothing); // popped back
      expect(await repo.findById('note-1'), isNull);
    });

    testWidgets('a failed note shows a Tekrar Dene button that re-triggers processing',
        (tester) async {
      final item = note(processingStatus: 'failed');
      final repo = FakeItemRepository(initialItems: [item]);

      await tester.pumpWidget(wrap(item, repo: repo));
      await tester.pumpAndSettle();

      expect(find.text('İşlenemedi'), findsOneWidget);
      expect(find.text('Tekrar Dene'), findsOneWidget);

      await tester.tap(find.text('Tekrar Dene'));
      await tester.pumpAndSettle();

      expect(repo.retryProcessingCallCount, 1);
    });

    testWidgets('a completed note shows no processing chip at all', (tester) async {
      final item = note();
      await tester.pumpWidget(wrap(item, repo: FakeItemRepository(initialItems: [item])));
      await tester.pumpAndSettle();

      expect(find.text('İşlenemedi'), findsNothing);
      expect(find.text('İşlenmeyi bekliyor'), findsNothing);
      expect(find.text('Tekrar Dene'), findsNothing);
    });

    testWidgets(
        'processing finishing while the screen is already open updates it live '
        '(Faz 12, madde 8\'in aynısı, not ekranı için — see docs/roadmap.md)',
        (tester) async {
      final pending = note(processingStatus: 'pending');
      final repo = FakeItemRepository(initialItems: [pending]);

      await tester.pumpWidget(wrap(pending, repo: repo));
      await tester.pumpAndSettle();

      expect(find.text('İşlenmeyi bekliyor'), findsOneWidget);

      repo.updateItem(pending.copyWith(processingStatus: 'completed'));
      await tester.pumpAndSettle();

      expect(find.text('İşlenmeyi bekliyor'), findsNothing);
    });

    testWidgets(
        'processing finishing while the screen is open also refreshes tags/entities '
        '(denetim düzeltmesi — see docs/roadmap.md)', (tester) async {
      final pending = note(processingStatus: 'pending');
      final repo = FakeItemRepository(initialItems: [pending]);

      await tester.pumpWidget(wrap(pending, repo: repo));
      await tester.pumpAndSettle();

      expect(find.text('docker'), findsNothing);

      // Same AI pipeline run that finishes processing also produces
      // tags — itemTagsProvider fetched (and cached) "no tags" back
      // when this screen first opened.
      repo.tagsByItemId['note-1'] = ['docker'];
      repo.updateItem(pending.copyWith(processingStatus: 'completed'));
      await tester.pumpAndSettle();

      expect(find.text('docker'), findsOneWidget);
    });
  });
}
