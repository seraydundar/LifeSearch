import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/supabase_client_provider.dart';
import '../../../item/domain/entities/item.dart';
import '../../../item/presentation/providers/item_providers.dart';
import '../../data/remote/supabase_collection_repository.dart';
import '../../domain/entities/collection.dart';
import '../../domain/repositories/collection_repository.dart';

final collectionRepositoryProvider = Provider<CollectionRepository>((ref) {
  return SupabaseCollectionRepository(
    ref.watch(supabaseClientProvider),
    ref.watch(remoteItemDataSourceProvider),
  );
});

final collectionsProvider = StreamProvider<List<Collection>>((ref) {
  return ref.watch(collectionRepositoryProvider).watchCollections();
});

final collectionItemsProvider = StreamProvider.family<List<Item>, String>((ref, collectionId) {
  return ref.watch(collectionRepositoryProvider).watchCollectionItems(collectionId);
});

/// Which collections an item is already in — re-fetched each time the
/// "Add to Collection" sheet opens rather than kept live, since it's only
/// read while that sheet is on screen.
final itemCollectionIdsProvider =
    FutureProvider.autoDispose.family<List<String>, String>((ref, itemId) {
  return ref.watch(collectionRepositoryProvider).collectionIdsForItem(itemId);
});
