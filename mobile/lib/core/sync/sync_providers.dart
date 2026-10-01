import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/providers/auth_providers.dart';
import '../../features/collections/presentation/providers/collection_providers.dart';
import '../../features/item/presentation/providers/item_providers.dart';
import '../network/connectivity_provider.dart';
import 'sync_service.dart';

/// Lives outside both item/collection provider files since `SyncService` needs both, avoiding a
/// cross-feature import just for this. Kicked off on connectivity return, sign-in, and every local write.
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
    service.dispose();
  });

  service.syncSoon();
  return service;
});
