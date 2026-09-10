import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/error/failure.dart';
import '../../../../shared/widgets/life_search_bar.dart';
import '../../../item/domain/entities/item.dart';
import '../../../item/presentation/widgets/item_type_icon.dart';
import '../../domain/entities/search_result.dart';
import '../providers/search_providers.dart';

/// The "All/Images/Documents/Notes/Links/Audio" buckets from the
/// requirements doc, section 21 — each maps to the `ItemType`s it covers.
const _typeFilterBuckets = <String, Set<ItemType>>{
  'Images': {ItemType.image, ItemType.screenshot},
  'Documents': {ItemType.pdf, ItemType.document},
  'Notes': {ItemType.note},
  'Links': {ItemType.url},
  'Audio': {ItemType.audio},
};

enum _DatePreset { anytime, today, lastWeek, lastMonth }

extension on _DatePreset {
  String get label => switch (this) {
        _DatePreset.anytime => 'Her zaman',
        _DatePreset.today => 'Bugün',
        _DatePreset.lastWeek => 'Geçen hafta',
        _DatePreset.lastMonth => 'Geçen ay',
      };

  DateTime? get since {
    final now = DateTime.now();
    return switch (this) {
      _DatePreset.anytime => null,
      _DatePreset.today => DateTime(now.year, now.month, now.day),
      _DatePreset.lastWeek => now.subtract(const Duration(days: 7)),
      _DatePreset.lastMonth => now.subtract(const Duration(days: 30)),
    };
  }
}

/// The Search half of the "Tab: Search | Ask AI" layout (requirements
/// doc, section 23) — hosted inside `SearchHubScreen`'s `TabBarView`.
class SearchTab extends ConsumerStatefulWidget {
  const SearchTab({super.key, this.initialQuery});

  /// Run once on first build, e.g. a tag chip tapped from item detail.
  final String? initialQuery;

  @override
  ConsumerState<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends ConsumerState<SearchTab>
    with AutomaticKeepAliveClientMixin<SearchTab> {
  late final _controller = TextEditingController(text: widget.initialQuery);
  Timer? _debounce;
  _DatePreset _datePreset = _DatePreset.anytime;

  @override
  void initState() {
    super.initState();
    final initialQuery = widget.initialQuery;
    if (initialQuery != null && initialQuery.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _runSearch(initialQuery));
    }
  }

  @override
  bool get wantKeepAlive => true; // keep query/results when switching to Ask AI and back

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      ref.read(searchControllerProvider.notifier).clear();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 450), () {
      ref.read(searchControllerProvider.notifier).search(value);
    });
  }

  void _runSearch(String query) {
    _debounce?.cancel();
    ref.read(searchControllerProvider.notifier).search(query);
  }

  void _selectTypeBucket(String? label) {
    final types = label == null ? <ItemType>{} : _typeFilterBuckets[label]!;
    final current = ref.read(searchFiltersProvider);
    ref.read(searchFiltersProvider.notifier).state = current.copyWith(types: types);
    ref.read(searchControllerProvider.notifier).researchWithCurrentFilters();
  }

  void _selectDatePreset(_DatePreset preset) {
    setState(() => _datePreset = preset);
    final current = ref.read(searchFiltersProvider);
    ref.read(searchFiltersProvider.notifier).state = current.copyWith(dateFrom: preset.since);
    ref.read(searchControllerProvider.notifier).researchWithCurrentFilters();
  }

  void _openResult(SearchResult result) {
    final route = result.itemType == ItemType.note
        ? '/item/${result.itemId}/note'
        : '/item/${result.itemId}';
    // Search results don't carry the full Item the way Library rows do —
    // the detail screens re-fetch by id via this minimal stand-in.
    context.push(
      route,
      extra: Item(
        id: result.itemId,
        type: result.itemType,
        title: result.itemTitle,
        processingStatus: 'completed',
        favorite: false,
        createdAt: DateTime.now(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = ref.watch(searchControllerProvider);
    final recent = ref.watch(recentSearchesProvider).valueOrNull ?? [];
    final filters = ref.watch(searchFiltersProvider);
    final hasQuery = _controller.text.trim().isNotEmpty;
    final selectedBucket = _typeFilterBuckets.entries
        .firstWhere((e) => e.value.difference(filters.types).isEmpty && filters.types.isNotEmpty,
            orElse: () => const MapEntry('', {}))
        .key;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: LifeSearchBar(
            controller: _controller,
            suffixIcon: hasQuery
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _controller.clear();
                      setState(() {});
                      ref.read(searchControllerProvider.notifier).clear();
                    },
                  )
                : null,
            onChanged: (value) {
              setState(() {}); // toggles between recent-searches and results view
              _onChanged(value);
            },
            onSubmitted: _runSearch,
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              ChoiceChip(
                label: const Text('All'),
                selected: selectedBucket.isEmpty,
                onSelected: (_) => _selectTypeBucket(null),
              ),
              const SizedBox(width: 8),
              for (final label in _typeFilterBuckets.keys) ...[
                ChoiceChip(
                  label: Text(label),
                  selected: selectedBucket == label,
                  onSelected: (_) => _selectTypeBucket(label),
                ),
                const SizedBox(width: 8),
              ],
              PopupMenuButton<_DatePreset>(
                initialValue: _datePreset,
                onSelected: _selectDatePreset,
                itemBuilder: (context) => _DatePreset.values
                    .map((p) => PopupMenuItem(value: p, child: Text(p.label)))
                    .toList(),
                child: Chip(
                  avatar: const Icon(Icons.calendar_today_outlined, size: 16),
                  label: Text(_datePreset.label),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: !hasQuery
              ? _RecentSearches(
                  queries: recent,
                  onTap: (q) {
                    _controller.text = q;
                    _controller.selection = TextSelection.collapsed(offset: q.length);
                    setState(() {});
                    _runSearch(q);
                  },
                )
              : state.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (error, _) => _MessageState(
                    icon: Icons.error_outline,
                    message: error is Failure ? error.message : 'Arama başarısız oldu.',
                  ),
                  data: (results) {
                    if (results.isEmpty) {
                      return const _MessageState(
                        icon: Icons.search_off,
                        message: 'Sonuç bulunamadı.',
                      );
                    }
                    return ListView.separated(
                      itemCount: results.length,
                      separatorBuilder: (context, index) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final result = results[index];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: itemTypeColor(result.itemType).withValues(alpha: 0.15),
                            foregroundColor: itemTypeColor(result.itemType),
                            child: Icon(itemTypeIcon(result.itemType)),
                          ),
                          title: Text(result.itemTitle ?? 'Untitled', maxLines: 1),
                          subtitle:
                              Text(result.snippet, maxLines: 2, overflow: TextOverflow.ellipsis),
                          onTap: () => _openResult(result),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _RecentSearches extends StatelessWidget {
  const _RecentSearches({required this.queries, required this.onTap});

  final List<String> queries;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    if (queries.isEmpty) {
      return const _MessageState(
        icon: Icons.search,
        message: 'Arşivinde doğal dille arama yap.\nÖrn: "Docker hakkında kaydettiğim not"',
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text('Recent Searches', style: Theme.of(context).textTheme.titleSmall),
        ),
        for (final query in queries)
          ListTile(
            leading: const Icon(Icons.history),
            title: Text(query),
            onTap: () => onTap(query),
          ),
      ],
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
