import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../item/presentation/providers/item_providers.dart';

/// Every tag occurrence across the whole archive (requirements doc,
/// section 51; see docs/roadmap.md, Faz 11, madde 3) — the one piece of
/// the Analytics screen that isn't already sitting in the local cache
/// (tags aren't synced to Drift, see `ItemRepository.fetchTags`'s
/// docstring), so it's its own network-backed provider rather than
/// derived from [itemsProvider].
final analyticsTagOccurrencesProvider = FutureProvider.autoDispose<List<String>>((ref) {
  return ref.watch(itemRepositoryProvider).fetchAllTagNames();
});
