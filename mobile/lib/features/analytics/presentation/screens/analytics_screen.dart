import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../item/domain/entities/item.dart';
import '../../../item/presentation/providers/item_providers.dart';
import '../../../item/presentation/widgets/item_type_icon.dart';
import '../../../settings/domain/storage_usage.dart';
import '../../domain/analytics.dart';
import '../providers/analytics_providers.dart';

/// Requirements doc, section 51 — see docs/roadmap.md, Faz 11, madde 3.
/// Everything here reads from [itemsProvider] (the same local-first
/// stream Home/Library use, `private` items already excluded unless
/// revealed) except [analyticsTagOccurrencesProvider], which needs a
/// connection — tags aren't cached locally.
class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(itemsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Analytics')),
      body: itemsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Yüklenemedi: $error')),
        data: (items) => _AnalyticsBody(items: items),
      ),
    );
  }
}

class _AnalyticsBody extends ConsumerWidget {
  const _AnalyticsBody({required this.items});

  final List<Item> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    final byType = countsByType(items).entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxTypeCount = byType.isEmpty ? 0 : byType.first.value;

    final months = itemsPerMonth(items);
    final maxMonthCount = months.fold(0, (max, m) => m.count > max ? m.count : max);

    final tagsAsync = ref.watch(analyticsTagOccurrencesProvider);

    // Only known once private items are actually revealed — `items`
    // above already excludes them, so counting *that* list would
    // always read zero (Faz 11, madde 2's own hiding doing its job) —
    // this asks the raw, unfiltered stream instead, but only shown once
    // the same reveal gate everything else respects has been passed.
    final revealed = ref.watch(privateItemsRevealedProvider);
    final privateStat =
        revealed ? privateCount(ref.watch(allItemsIncludingPrivateProvider).valueOrNull ?? []) : null;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Expanded(child: _StatTile(label: 'Toplam', value: '${totalItemCount(items)}')),
            const SizedBox(width: 12),
            Expanded(child: _StatTile(label: 'Favori', value: '${favoriteCount(items)}')),
            const SizedBox(width: 12),
            Expanded(
              child: _StatTile(label: 'Depolama', value: formatBytes(totalStorageBytes(items))),
            ),
            if (privateStat != null) ...[
              const SizedBox(width: 12),
              Expanded(child: _StatTile(label: 'Private', value: '$privateStat')),
            ],
          ],
        ),
        const SizedBox(height: 28),
        Text('Türe göre dağılım', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        if (byType.isEmpty)
          Text('Henüz içerik yok.', style: theme.textTheme.bodyMedium)
        else
          for (final entry in byType)
            _TypeBar(type: entry.key, count: entry.value, maxCount: maxTypeCount),
        const SizedBox(height: 28),
        Text('Son ${months.length} ayda eklenen', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        _MonthlyBars(months: months, maxCount: maxMonthCount),
        const SizedBox(height: 28),
        Text('En yaygın etiketler', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        tagsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, _) =>
              Text('Etiketler yüklenemedi — bağlantını kontrol et.', style: theme.textTheme.bodyMedium),
          data: (occurrences) {
            final tags = topTags(occurrences);
            if (tags.isEmpty) return Text('Henüz etiket yok.', style: theme.textTheme.bodyMedium);
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (name, count) in tags) Chip(label: Text('$name · $count')),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
        child: Column(
          children: [
            Text(value, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(label, style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

/// One horizontal bar per content type, longest (i.e. most common) first
/// — magnitude is the job, so a sorted bar list rather than a pie slice
/// count is the right form. Colored with the same fixed, non-cycled
/// per-type palette (`itemTypeColor`) Library/Home/search results
/// already use, with its own icon+label directly beside it — that's the
/// direct label, no separate legend needed for a single-series-per-row
/// chart like this.
class _TypeBar extends StatelessWidget {
  const _TypeBar({required this.type, required this.count, required this.maxCount});

  final ItemType type;
  final int count;
  final int maxCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fraction = maxCount == 0 ? 0.0 : count / maxCount;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(itemTypeIcon(type), size: 18, color: itemTypeColor(type)),
          const SizedBox(width: 8),
          SizedBox(
            width: 90,
            child: Text(itemTypeLabel(type), style: theme.textTheme.bodyMedium),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Stack(
                children: [
                  Container(height: 10, color: theme.colorScheme.surfaceContainerHighest),
                  FractionallySizedBox(
                    widthFactor: fraction,
                    child: Container(height: 10, color: itemTypeColor(type)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 28,
            child: Text('$count', textAlign: TextAlign.right, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

/// A single series over time (item count per month) — one hue, the
/// app's own brand color, never a rainbow across bars that all mean the
/// same thing. Each bar is directly labeled with its own count, so no
/// axis/legend is needed for a chart this small.
class _MonthlyBars extends StatelessWidget {
  const _MonthlyBars({required this.months, required this.maxCount});

  final List<MonthlyCount> months;
  final int maxCount;

  static const _maxBarHeight = 60.0;
  static const _minBarHeight = 4.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 100,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final month in months)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text('${month.count}', style: theme.textTheme.labelSmall),
                    const SizedBox(height: 4),
                    Container(
                      height: maxCount == 0
                          ? _minBarHeight
                          : _minBarHeight + _maxBarHeight * (month.count / maxCount),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(DateFormat('MMM').format(month.month), style: theme.textTheme.labelSmall),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
