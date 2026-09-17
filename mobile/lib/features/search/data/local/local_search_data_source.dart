import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../item/domain/entities/item.dart';
import '../../domain/entities/search_filters.dart';
import '../../domain/entities/search_result.dart';
import 'tfidf_ranker.dart';

/// On-device relevance ranking over the local Drift cache (requirements
/// doc, section 25-33: "offline-first ... + offline search") — used
/// when the backend's real semantic/hybrid search can't be reached,
/// see `OfflineFallbackSearchRepository`.
///
/// Ranks with a from-scratch TF-IDF + cosine similarity model
/// (`tfidf_ranker.dart` — Faz 11, madde 6b, see docs/roadmap.md) rather
/// than a plain substring scan: a multi-word query matches even when
/// its words land in different fields or a different order, and
/// results are ordered by how much of the query's vocabulary they
/// actually contain instead of just "newest first". **Not** a neural
/// embedding — it can't match synonyms/paraphrases, only shared
/// vocabulary (after lowercasing and Unicode-aware tokenizing) — see
/// `tfidf_ranker.dart`'s own docstring for why that trade-off was made.
///
/// Matches title, description, a note's own body, a link's URL/filename,
/// an item's tags, and — since P2-07 (docs/requirements-audit-2026-09-13.md)
/// — its `extractedText` (`item_contents.raw_text`: OCR text for a scanned
/// PDF/screenshot, a PDF/DOCX/TXT's extracted body, an audio transcript, or
/// a scraped webpage's article text; see `LocalItems.extractedText`'s own
/// docstring). Entities and `item_contents.summary` still aren't synced to
/// Drift, so those remain unsearchable offline — a real but narrower
/// bounded limitation than before.
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
    // Same rule as the remote RPCs (P1-02, docs/requirements-audit-2026-09-13.md,
    // see 0017_search_excludes_private.sql): exclude private items at the
    // query itself rather than counting on `_hidePrivateResults`'
    // cross-check downstream to be the only thing catching this.
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

  /// [itemIds] -> its tag names, for [_combinedText]. A single `WHERE
  /// item_id IN (...)` rather than one query per item — the local
  /// equivalent of `fetchAllItemTagRows`' bulk-fetch-then-map shape on the
  /// sync side.
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

    // No literal substring match — a multi-word query whose terms
    // landed in different fields (or a different order) than one
    // contiguous run of characters. TF-IDF still ranked this as a
    // match, so fall back to an excerpt around the first shared token
    // instead of showing nothing.
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
