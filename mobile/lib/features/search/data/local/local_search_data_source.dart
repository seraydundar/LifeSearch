import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../item/domain/entities/item.dart';
import '../../domain/entities/search_filters.dart';
import '../../domain/entities/search_result.dart';

/// Keyword fallback over the local Drift cache (requirements doc,
/// section 25-33: "offline-first ... + offline keyword search") — used
/// when the backend's semantic/hybrid search can't be reached, see
/// `OfflineFallbackSearchRepository`.
///
/// Matches only what's actually cached locally: title, description, a
/// note's own body, and a link's URL/filename. OCR text and AI-generated
/// descriptions for images/PDFs live in Supabase's `item_contents`,
/// never synced to Drift, so those aren't searchable offline — a real
/// but bounded limitation of "the phone has no copy of that text".
class LocalSearchDataSource {
  LocalSearchDataSource(this._db);

  final AppDatabase _db;

  static const _excerptRadius = 60;

  Future<List<SearchResult>> search(
    String? userId,
    String query, {
    SearchFilters filters = const SearchFilters(),
  }) async {
    if (userId == null) return [];
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return [];

    final q = _db.select(_db.localItems)..where((t) => t.userId.equals(userId));
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
    final matches = <(LocalItem, String)>[];
    for (final row in rows) {
      final snippet = _matchingSnippet(row, needle);
      if (snippet != null) matches.add((row, snippet));
    }
    // No real ranking offline (no embeddings, no ts_rank) — newest first
    // is the least-surprising order for a plain keyword fallback.
    matches.sort((a, b) => b.$1.createdAt.compareTo(a.$1.createdAt));

    return matches
        .map((match) => SearchResult(
              itemId: match.$1.id,
              itemType: ItemTypeX.fromDbValue(match.$1.type),
              itemTitle: match.$1.title,
              snippet: match.$2,
              similarity: 0,
            ))
        .toList();
  }

  String? _matchingSnippet(LocalItem item, String needle) {
    for (final field in [item.noteContent, item.description, item.title, item.sourceUrl]) {
      if (field == null) continue;
      final index = field.toLowerCase().indexOf(needle);
      if (index != -1) return _excerpt(field, index, needle.length);
    }
    return null;
  }

  String _excerpt(String text, int matchIndex, int matchLength) {
    final start = (matchIndex - _excerptRadius).clamp(0, text.length);
    final end = (matchIndex + matchLength + _excerptRadius).clamp(0, text.length);
    final prefix = start > 0 ? '…' : '';
    final suffix = end < text.length ? '…' : '';
    return '$prefix${text.substring(start, end).trim()}$suffix';
  }
}
