import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_provider.dart';
import '../../../../core/network/supabase_client_provider.dart';
import '../../../../core/sync/sync_providers.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../item/domain/entities/item.dart';
import '../../../item/presentation/providers/item_providers.dart';
import '../../data/local/collection_local_data_source.dart';
import '../../data/remote/remote_collection_data_source.dart';
import '../../data/repositories/offline_collection_repository.dart';
import '../../domain/entities/collection.dart';
import '../../domain/repositories/collection_repository.dart';

final collectionLocalDataSourceProvider = Provider<CollectionLocalDataSource>((ref) {
  return CollectionLocalDataSource(ref.watch(appDatabaseProvider));
});

final remoteCollectionDataSourceProvider = Provider<RemoteCollectionDataSource>((ref) {
  return RemoteCollectionDataSource(ref.watch(supabaseClientProvider));
});

final collectionRepositoryProvider = Provider<CollectionRepository>((ref) {
  // Forces a rebuild on account switch instead of staying bound to the first user.
  ref.watch(currentUserIdProvider);
  return OfflineCollectionRepository(
    local: ref.watch(collectionLocalDataSourceProvider),
    remote: ref.watch(remoteCollectionDataSourceProvider),
    queue: ref.watch(syncQueueDataSourceProvider),
    syncService: ref.watch(syncServiceProvider),
  );
});

final collectionsProvider = StreamProvider<List<Collection>>((ref) {
  return ref.watch(collectionRepositoryProvider).watchCollections();
});

final collectionItemsProvider = StreamProvider.family<List<Item>, String>((ref, collectionId) {
  final includePrivate = ref.watch(privateItemsRevealedProvider);
  return ref
      .watch(collectionRepositoryProvider)
      .watchCollectionItems(collectionId, includePrivate: includePrivate);
});

/// Re-fetched each time the "Add to Collection" sheet opens rather than kept live.
final itemCollectionIdsProvider =
    FutureProvider.autoDispose.family<List<String>, String>((ref, itemId) {
  return ref.watch(collectionRepositoryProvider).collectionIdsForItem(itemId);
});
