import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lifesearch/core/network/api_client_provider.dart';
import 'package:lifesearch/features/auth/presentation/providers/auth_providers.dart';
import 'package:lifesearch/features/auth/domain/entities/app_user.dart';
import 'package:lifesearch/features/item/domain/entities/item.dart';
import 'package:lifesearch/features/item/presentation/providers/item_providers.dart';
import 'package:lifesearch/features/settings/presentation/screens/settings_screen.dart';

import '../fakes/fake_auth_repository.dart';
import '../fakes/fake_item_repository.dart';

void main() {
  Widget wrap({FakeItemRepository? repo, bool aiAvailable = false}) {
    return ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(initialUser: const AppUser(id: 'u1', email: 'test@example.com')),
        ),
        itemRepositoryProvider.overrideWithValue(repo ?? FakeItemRepository()),
        // A live Drift stream (rather than this) leaves a pending timer on
        // widget-tree disposal in tests — see local_search_data_source's
        // sibling tests for the same real-DB pattern used where it's
        // actually needed (a one-shot write, never a live `.watch()`).
        pendingSyncCountProvider.overrideWith((ref) => Stream.value(0)),
        apiClientProvider.overrideWithValue(null),
      ],
      child: MaterialApp.router(
        // The confirm dialog's buttons use go_router's `context.pop()`
        // (consistent with the rest of the app's confirm dialogs), which
        // needs a real GoRouter ancestor — a plain `MaterialApp(home:)`
        // doesn't have one.
        routerConfig: GoRouter(routes: [
          GoRoute(path: '/', builder: (context, state) => const SettingsScreen()),
        ]),
      ),
    );
  }

  testWidgets('shows the signed-in user\'s email', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.text('test@example.com'), findsOneWidget);
  });

  testWidgets('Storage tile sums fileSizeBytes across items', (tester) async {
    final repo = FakeItemRepository(initialItems: [
      Item(
        id: '1',
        type: ItemType.pdf,
        processingStatus: 'completed',
        favorite: false,
        createdAt: DateTime(2026, 1, 1),
        fileSizeBytes: 1024 * 500, // 500 KB
      ),
      Item(
        id: '2',
        type: ItemType.image,
        processingStatus: 'completed',
        favorite: false,
        createdAt: DateTime(2026, 1, 1),
        fileSizeBytes: 1024 * 524, // 524 KB — total 1024 KB = 1.0 MB
      ),
    ]);
    await tester.pumpWidget(wrap(repo: repo));
    await tester.pumpAndSettle();

    expect(find.textContaining('1.0 MB'), findsOneWidget);
  });

  testWidgets('AI Settings tile reflects whether a backend is configured', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.textContaining('devre dışı'), findsOneWidget);
  });

  testWidgets('Export tile is present and tappable', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.text('Export'), findsOneWidget);
    expect(find.byIcon(Icons.ios_share_outlined), findsOneWidget);
  });

  testWidgets('tapping Delete Account asks for confirmation first', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    // A plain `ListView(children:)` still only mounts elements within the
    // viewport + cache extent — `ensureVisible` needs the element to
    // already exist, so scroll it into view instead.
    await tester.scrollUntilVisible(find.text('Delete Account'), 200);
    await tester.tap(find.text('Delete Account'));
    await tester.pumpAndSettle();

    expect(find.text('Bu işlem GERİ ALINAMAZ. Tüm içeriklerin, koleksiyonların ve hesabın '
        'kalıcı olarak silinecek.'), findsOneWidget);
  });

  testWidgets('cancelling the confirmation does not attempt deletion', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    // A plain `ListView(children:)` still only mounts elements within the
    // viewport + cache extent — `ensureVisible` needs the element to
    // already exist, so scroll it into view instead.
    await tester.scrollUntilVisible(find.text('Delete Account'), 200);
    await tester.tap(find.text('Delete Account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();

    // No backend configured (apiClientProvider is null) — if deletion had
    // been attempted, this error snackbar would be showing.
    expect(find.textContaining('Backend bağlantısı ayarlanmamış'), findsNothing);
  });

  testWidgets('confirming without a configured backend surfaces the error', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    // A plain `ListView(children:)` still only mounts elements within the
    // viewport + cache extent — `ensureVisible` needs the element to
    // already exist, so scroll it into view instead.
    await tester.scrollUntilVisible(find.text('Delete Account'), 200);
    await tester.tap(find.text('Delete Account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hesabı Sil'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Backend bağlantısı ayarlanmamış'), findsOneWidget);
  });
}
