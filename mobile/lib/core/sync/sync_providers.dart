import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/providers/auth_providers.dart';
import '../../features/collections/presentation/providers/collection_providers.dart';
import '../../features/item/presentation/providers/item_providers.dart';
import '../network/connectivity_provider.dart';
import 'sync_service.dart';

/// Lives outside both `item_providers.dart` and `collection_providers.dart`
/// on purpose: `SyncService` now reconciles both items and collections (one
/// `sync_queue` table, one coordinator — see `SyncService`'s doc comment),
/// so it needs providers from both features. Defining it in either feature
/// file would make that file import the other, both ways, for no reason
/// beyond this one provider.
///
/// Reconciles local cache ↔ Supabase. Kicked off whenever connectivity
/// returns or the user signs in; `itemRepositoryProvider` and
/// `collectionRepositoryProvider` also nudge it after every local write
/// (see `SyncService.syncSoon`).
final syncServiceProvider = Provider<SyncService>((ref) {
  final service = SyncService(
    local: ref.watch(itemLocalDataSourceProvider),
    remote: ref.watch(remoteItemDataSourceProvider),
    localCollections: ref.watch(collectionLocalDataSourceProvider),
    remoteCollections: ref.watch(remoteCollectionDataSourceProvider),
    queue: ref.watch(syncQueueDataSourceProvider),
    aiTrigger: ref.watch(aiProcessingTriggerProvider),
  );

  final onlineSub = ref.listen(isOnlineProvider, (previous, next) {
    if (next.valueOrNull == true) service.syncSoon();
  });
  final authSub = ref.listen(authStateChangesProvider, (previous, next) {
    if (next.valueOrNull != null) service.syncSoon();
  });
  ref.onDispose(() {
    onlineSub.close();
    authSub.close();
  });

  service.syncSoon();
  return service;
});
