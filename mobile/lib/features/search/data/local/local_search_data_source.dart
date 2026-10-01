import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../item/domain/entities/item.dart';
import '../../domain/entities/search_filters.dart';
import '../../domain/entities/search_result.dart';
import 'tfidf_ranker.dart';

/// On-device TF-IDF + cosine ranking, used when the backend's real search is
/// unreachable. Not embeddings — no synonym/paraphrase matching. Entities and
/// `item_contents.summary` aren't synced to Drift, so they stay unsearchable offline.
class LocalSearchDataSource {
  LocalSearchDataSource(this._db);

  final AppDatabase _db;

  static const _excerptRadius = 60;

  Future<List<SearchResult>> search(
    String? userId,
    String query, {
    SearchFilters filters = const SearchFilters(),
    bool includePrivate = false,
  }) async {
    if (userId == null) return [];
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) return [];

    final q = _db.select(_db.localItems)..where((t) => t.userId.equals(userId));
    if (!includePrivate) {
      q.where((t) => t.private.equals(false));
    }
    if (filters.types.isNotEmpty) {
      final dbValues = filters.types.map((t) => t.dbValue).toList();
      q.where((t) => t.type.isIn(dbValues));
    }
    if (filters.dateFrom != null) {
      q.where((t) => t.createdAt.isBiggerOrEqualValue(filters.dateFrom!));
    }
    if (filters.dateTo != null) {
      q.where((t) => t.createdAt.isSmallerOrEqualValue(filters.dateTo!));
    }

    final rows = await q.get();
    if (rows.isEmpty) return [];

    final tagsByItemId = await _tagsForItems(rows.map((r) => r.id).toList());
    final documents = [
      for (final row in rows)
        TfidfDocument(id: row.id, text: _combinedText(row, tagsByItemId[row.id] ?? const [])),
    ];
    final ranked = rankByTfidf(query: trimmedQuery, documents: documents);
    if (ranked.isEmpty) return [];

    final rowsById = {for (final row in rows) row.id: row};
    final queryTokens = tokenize(trimmedQuery);

    return [
      for (final entry in ranked)
        SearchResult(
          itemId: entry.key,
          itemType: ItemTypeX.fromDbValue(rowsById[entry.key]!.type),
          itemTitle: rowsById[entry.key]!.title,
          snippet: _snippetFor(rowsById[entry.key]!, trimmedQuery, queryTokens),
          similarity: entry.value,
        ),
    ];
  }

  Future<Map<String, List<String>>> _tagsForItems(List<String> itemIds) async {
    if (itemIds.isEmpty) return {};
    final rows = await (_db.select(_db.localTags)..where((t) => t.itemId.isIn(itemIds))).get();
    final tagsByItemId = <String, List<String>>{};
    for (final row in rows) {
      tagsByItemId.putIfAbsent(row.itemId, () => []).add(row.name);
    }
    return tagsByItemId;
  }

  String _combinedText(LocalItem item, List<String> tags) {
    final fields = [item.noteContent, item.description, item.title, item.sourceUrl, item.extractedText]
        .where((field) => field != null && field.isNotEmpty)
        .cast<String>();
    return [...fields, ...tags].join(' ');
  }

  String _snippetFor(LocalItem item, String query, List<String> queryTokens) {
    final fields = [
      item.noteContent,
      item.description,
      item.title,
      item.sourceUrl,
      item.extractedText,
    ];
    final needle = query.toLowerCase();

    for (final field in fields) {
      if (field == null) continue;
      final index = field.toLowerCase().indexOf(needle);
      if (index != -1) return _excerpt(field, index, needle.length);
    }

    // No substring match, but TF-IDF ranked it — fall back to the first shared token.
    for (final field in fields) {
      if (field == null) continue;
      final lower = field.toLowerCase();
      for (final token in queryTokens) {
        final index = lower.indexOf(token);
        if (index != -1) return _excerpt(field, index, token.length);
      }
    }

    return fields.firstWhere((f) => f != null && f.isNotEmpty, orElse: () => '') ?? '';
  }

  String _excerpt(String text, int matchIndex, int matchLength) {
    final start = (matchIndex - _excerptRadius).clamp(0, text.length);
    final end = (matchIndex + matchLength + _excerptRadius).clamp(0, text.length);
    final prefix = start > 0 ? '…' : '';
    final suffix = end < text.length ? '…' : '';
    return '$prefix${text.substring(start, end).trim()}$suffix';
  }
}
