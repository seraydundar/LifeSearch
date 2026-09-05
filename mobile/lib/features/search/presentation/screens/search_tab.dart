import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/error/failure.dart';
import '../../../item/domain/entities/item.dart';
import '../../../item/presentation/widgets/item_type_icon.dart';
import '../../domain/entities/search_result.dart';
import '../providers/search_providers.dart';

/// The Search half of the "Tab: Search | Ask AI" layout (requirements
/// doc, section 23) — hosted inside `SearchHubScreen`'s `TabBarView`.
class SearchTab extends ConsumerStatefulWidget {
  const SearchTab({super.key});

  @override
  ConsumerState<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends ConsumerState<SearchTab>
    with AutomaticKeepAliveClientMixin<SearchTab> {
  final _controller = TextEditingController();
  Timer? _debounce;

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
    final hasQuery = _controller.text.trim().isNotEmpty;
    final theme = Theme.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _controller,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search your life...',
              prefixIcon: const Icon(Icons.search),
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
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (value) {
              setState(() {}); // toggles between recent-searches and results view
              _onChanged(value);
            },
            onSubmitted: _runSearch,
          ),
        ),
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
                          leading: CircleAvatar(child: Icon(itemTypeIcon(result.itemType))),
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
