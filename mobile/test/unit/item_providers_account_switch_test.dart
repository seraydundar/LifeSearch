import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:lifesearch/core/database/app_database.dart';
import 'package:lifesearch/core/database/database_provider.dart';
import 'package:lifesearch/core/error/failure.dart';
import 'package:lifesearch/core/network/supabase_client_provider.dart';
import 'package:lifesearch/core/sync/sync_providers.dart';
import 'package:lifesearch/core/sync/sync_service.dart';
import 'package:lifesearch/features/auth/domain/entities/app_user.dart';
import 'package:lifesearch/features/auth/presentation/providers/auth_providers.dart';
import 'package:lifesearch/features/collections/presentation/providers/collection_providers.dart';
import 'package:lifesearch/features/item/data/remote/remote_item_data_source.dart';
import 'package:lifesearch/features/item/presentation/providers/item_providers.dart';

/// `RemoteItemDataSource.userId` already re-reads the live Supabase
/// session fresh on every access (see that class) — this stand-in mirrors
/// that exactly: **one stable instance** (never rebuilt itself, exactly
/// like production's real `remoteItemDataSourceProvider`, which always
/// returns the same object since `supabaseClientProvider` never changes)
/// whose `userId` getter reads whatever [_currentUserId] returns *at
/// call time*. If this test instead made the fake's identity itself
/// change on account switch, it would accidentally also fix
/// `itemRepositoryProvider`'s missing dependency all on its own — via
/// `ref.watch(remoteItemDataSourceProvider)`, which it has regardless of
/// the fix under test — and the test would pass even with that fix
/// reverted, which was caught and is exactly why this is written this way.
class _AccountAwareRemoteItemDataSource extends RemoteItemDataSource {
  _AccountAwareRemoteItemDataSource(super.client, this._currentUserId);

  final String? Function() _currentUserId;

  @override
  String get userId {
    final id = _currentUserId();
    if (id == null) throw const AuthFailure('Oturum bulunamadı.');
    return id;
  }
}

void main() {
  // Faz 12 — denetim düzeltmesi (see docs/roadmap.md): `itemsProvider`/
  // `itemRepositoryProvider` used to read the signed-in user's id exactly
  // once, then bind their Drift stream to that id forever — switching
  // accounts within the same app session (no full restart) left Home/
  // Library showing the *previous* account's items. This reproduces that
  // exact scenario against the real provider graph (a real in-memory
  // Drift DB, real `itemRepositoryProvider`/`itemsProvider`), not just the
  // isolated helper — only `remoteItemDataSourceProvider`'s notion of
  // "who's signed in" is faked, since a real Supabase session isn't
  // practical to stand up here.
  test(
      "switching accounts rebuilds itemsProvider so it shows the new account's items, "
      'not the previous one\'s', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await db.into(db.localItems).insert(LocalItemsCompanion.insert(
          id: 'a-item',
          userId: 'user-a',
          type: 'note',
          title: const Value('A\'nın notu'),
          createdAt: DateTime(2026, 1, 1),
        ));
    await db.into(db.localItems).insert(LocalItemsCompanion.insert(
          id: 'b-item',
          userId: 'user-b',
          type: 'note',
          title: const Value('B\'nin notu'),
          createdAt: DateTime(2026, 1, 1),
        ));

    final authController = StreamController<AppUser?>();
    addTearDown(authController.close);
    final dummyClient = SupabaseClient('https://example.invalid', 'dummy-anon-key');

    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      authStateChangesProvider.overrideWith((ref) => authController.stream),
      // Every other real provider that touches Supabase (e.g.
      // `remoteCollectionDataSourceProvider`, pulled in transitively via
      // `syncServiceProvider` below) needs *some* client instance to
      // build without `Supabase.initialize()` — this one never actually
      // makes a request in this test.
      supabaseClientProvider.overrideWithValue(dummyClient),
      remoteItemDataSourceProvider.overrideWith((ref) {
        // `ref.read` inside the closure (not `ref.watch` on the provider
        // itself) — this instance must NOT be rebuilt when the current
        // user changes, only its `userId` getter's *answer* should
        // differ, exactly like production's real one.
        return _AccountAwareRemoteItemDataSource(
          dummyClient,
          () => ref.read(currentUserIdProvider),
        );
      }),
      // Real sub-objects (all cheap, no network at construction time) —
      // just never trigger an actual sync, since this test only exercises
      // reads.
      syncServiceProvider.overrideWith((ref) {
        return SyncService(
          local: ref.watch(itemLocalDataSourceProvider),
          remote: ref.watch(remoteItemDataSourceProvider),
          localCollections: ref.watch(collectionLocalDataSourceProvider),
          remoteCollections: ref.watch(remoteCollectionDataSourceProvider),
          queue: ref.watch(syncQueueDataSourceProvider),
          aiTrigger: ref.watch(aiProcessingTriggerProvider),
        );
      }),
    ]);
    addTearDown(container.dispose);

    // Providers are lazy — force `authStateChangesProvider` to actually
    // subscribe to `authController.stream` *before* pushing events,
    // otherwise the first push races the subscription being set up.
    container.listen(authStateChangesProvider, (_, _) {});

    authController.add(const AppUser(id: 'user-a', email: 'a@example.com'));
    await Future<void>.delayed(Duration.zero); // let the stream event land

    final asA = await container.read(itemsProvider.future);
    expect(asA.map((i) => i.id), ['a-item']);

    authController.add(const AppUser(id: 'user-b', email: 'b@example.com'));
    await Future<void>.delayed(Duration.zero);

    final asB = await container.read(itemsProvider.future);
    expect(asB.map((i) => i.id), ['b-item']);
  });
}
