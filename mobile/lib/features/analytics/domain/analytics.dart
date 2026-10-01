import '../../item/domain/entities/item.dart';

// Pure functions over the locally cached items; only [topTags] needs a
// network round trip, since tags aren't cached locally.

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

  /// Bucket key (1st of month, local time), not a real "created at" timestamp.
  final DateTime month;
  final int count;
}

/// Item count per calendar month for the last [months] months (current
/// one included), oldest first, zero-filled so every month is present.
List<MonthlyCount> itemsPerMonth(List<Item> items, {int months = 6, DateTime? now}) {
  final today = now ?? DateTime.now();
  final buckets = <DateTime, int>{};
  for (var i = months - 1; i >= 0; i--) {
    // DateTime normalizes an out-of-range month (e.g. month 0 -> last December) on its own.
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

/// Most frequent tag names, most common first. `allTagOccurrences` must stay
/// un-deduplicated (one entry per item-tag association) since counting
/// duplicates is the point.
List<(String, int)> topTags(List<String> allTagOccurrences, {int limit = 10}) {
  final counts = <String, int>{};
  for (final tag in allTagOccurrences) {
    counts[tag] = (counts[tag] ?? 0) + 1;
  }
  final sorted = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  return [for (final e in sorted.take(limit)) (e.key, e.value)];
}
