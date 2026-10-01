/// PostgREST silently truncates past its configured max-rows cap instead of erroring, and `SyncService`
/// treats a row missing from the response as deleted — so this fetches every page, advancing by the
/// actual rows returned (not [pageSize], which could misidentify a server-capped page as the last one),
/// and stops only on a genuinely empty page.
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
