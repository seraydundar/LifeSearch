import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../item/presentation/providers/item_providers.dart';

/// Tags aren't cached locally, so this is network-backed rather than derived
/// from [itemsProvider].
final analyticsTagOccurrencesProvider = FutureProvider.autoDispose<List<String>>((ref) {
  return ref.watch(itemRepositoryProvider).fetchAllTagNames();
});
