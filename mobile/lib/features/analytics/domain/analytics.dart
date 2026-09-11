import '../../item/domain/entities/item.dart';

/// Analytics screen (requirements doc, section 51 — see docs/roadmap.md,
/// Faz 11, madde 3). Pure functions over whatever's already in the local
/// cache (`itemsProvider`) — no separate backend endpoint, same
/// offline-first contract as everywhere else in this app; only
/// [topTags] needs a network round trip, since tags aren't cached
/// locally (see `ItemRepository.fetchTags`'s docstring).

int totalItemCount(List<Item> items) => items.length;

int favoriteCount(List<Item> items) => items.where((item) => item.favorite).length;

int privateCount(List<Item> items) => items.where((item) => item.private).length;

Map<ItemType, int> countsByType(List<Item> items) {
  final counts = <ItemType, int>{};
  for (final item in items) {
    counts[item.type] = (counts[item.type] ?? 0) + 1;
  }
  return counts;
}

class MonthlyCount {
  const MonthlyCount(this.month, this.count);

  /// Always the 1st of the month, local time — a bucket key, not a real
  /// "created at" timestamp.
  final DateTime month;
  final int count;
}

/// Item count per calendar month for the last [months] months (the
/// current one included), oldest first. Always exactly [months] entries
/// — zero-filled for a month nothing was added in — so a bar row never
/// has to guess whether a missing entry means "no data" or "not asked
/// for" (see `AnalyticsScreen`'s monthly bars).
List<MonthlyCount> itemsPerMonth(List<Item> items, {int months = 6, DateTime? now}) {
  final today = now ?? DateTime.now();
  final buckets = <DateTime, int>{};
  for (var i = months - 1; i >= 0; i--) {
    // DateTime normalizes an out-of-range month (e.g. month 0 -> last
    // December) on its own — no manual year rollover needed here.
    final month = DateTime(today.year, today.month - i);
    buckets[DateTime(month.year, month.month)] = 0;
  }

  for (final item in items) {
    final key = DateTime(item.createdAt.year, item.createdAt.month);
    final current = buckets[key];
    if (current != null) buckets[key] = current + 1;
  }

  final entries = buckets.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
  return [for (final e in entries) MonthlyCount(e.key, e.value)];
}

/// Most frequent tag names, most common first. `allTagOccurrences` is a
/// flat list with one entry per (item, tag) association (see
/// `ItemRepository.fetchAllTagNames()`) — deliberately not deduplicated
/// going in, since counting the duplicates is the whole point.
List<(String, int)> topTags(List<String> allTagOccurrences, {int limit = 10}) {
  final counts = <String, int>{};
  for (final tag in allTagOccurrences) {
    counts[tag] = (counts[tag] ?? 0) + 1;
  }
  final sorted = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  return [for (final e in sorted.take(limit)) (e.key, e.value)];
}
