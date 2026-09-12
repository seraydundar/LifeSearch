/// Supabase's PostgREST caps how many rows a single request returns (the
/// project's configured "max rows" — often 1000, but never guaranteed to
/// be exactly that) — a `.select()` with no explicit `.range()` doesn't
/// error past that limit, it silently truncates.
///
/// `SyncService` treats "not in the fetched response" as "deleted on the
/// server" (Faz 12, madde 9, denetim düzeltmesi — see docs/roadmap.md):
/// for an archive larger than one page, that used to mean every row past
/// the cap looked deleted and got wiped from the local cache on the very
/// next sync, even though it's still on the server, just wasn't in this
/// particular response.
///
/// Fetches every page, advancing the offset by however many rows a page
/// *actually* returned rather than the requested [pageSize] — safe even
/// if the server's own cap is smaller than [pageSize] (comparing the
/// returned length to the *requested* size would misidentify a
/// server-capped page as the last one). Stops the moment a page comes
/// back empty, the one signal that's reliable regardless of what the
/// server's real cap turns out to be.
Future<List<Map<String, dynamic>>> fetchAllPages(
  Future<List<Map<String, dynamic>>> Function(int from, int to) fetchPage, {
  int pageSize = 1000,
}) async {
  final rows = <Map<String, dynamic>>[];
  var offset = 0;
  while (true) {
    final page = await fetchPage(offset, offset + pageSize - 1);
    if (page.isEmpty) break;
    rows.addAll(page);
    offset += page.length;
  }
  return rows;
}
