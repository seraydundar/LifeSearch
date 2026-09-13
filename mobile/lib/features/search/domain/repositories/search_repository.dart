import '../entities/search_filters.dart';
import '../entities/search_result.dart';

abstract interface class SearchRepository {
  /// [includePrivate] must only ever be the live value of
  /// `privateItemsRevealedProvider` — the backend excludes private items
  /// by default (P1-02, docs/requirements-audit-2026-09-13.md) and only
  /// includes them once the device's own private reveal is unlocked.
  Future<List<SearchResult>> search(
    String query, {
    SearchFilters filters = const SearchFilters(),
    bool includePrivate = false,
  });

  /// Other items whose content is semantically close to this one
  /// (requirements doc, section 47) — no query text involved. Same
  /// [includePrivate] contract as [search].
  Future<List<SearchResult>> related(String itemId, {bool includePrivate = false});
}
