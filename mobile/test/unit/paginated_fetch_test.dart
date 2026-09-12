import 'package:flutter_test/flutter_test.dart';
import 'package:lifesearch/core/network/paginated_fetch.dart';

void main() {
  // Faz 12, madde 9 (denetim düzeltmesi — see docs/roadmap.md): a plain
  // unpaginated fetch silently truncated past PostgREST's row cap, and
  // SyncService treated everything past that cap as "deleted on the
  // server" — wiping local rows that were still there, just not in that
  // one response. These test the pagination loop in isolation, with no
  // Supabase/HTTP involved at all, since that's where the actual bug and
  // its fix live — `RemoteItemDataSource`/`RemoteCollectionDataSource`
  // are now thin call-sites over this.
  group('fetchAllPages', () {
    List<Map<String, dynamic>> rowsFrom(int start, int count) {
      return List.generate(count, (i) => {'id': '${start + i}'});
    }

    test('a short first page still gets one confirming empty call before stopping', () async {
      final calls = <(int, int)>[];
      final result = await fetchAllPages((from, to) {
        calls.add((from, to));
        // Only 3 rows total — a *short* page alone doesn't prove that
        // (see the "server caps below pageSize" test below), only an
        // actually-empty one does, so a second, confirming call happens
        // even though the first page was already short.
        return Future.value(from > 0 ? const [] : rowsFrom(0, 3));
      }, pageSize: 1000);

      expect(calls, [(0, 999), (3, 1002)]);
      expect(result.map((r) => r['id']), ['0', '1', '2']);
    });

    test('an archive spanning multiple pages fetches every page and concatenates them',
        () async {
      // 2500 rows total, pageSize 1000 — pages of 1000, 1000, 500, then
      // one final empty call. A short (500-row) page isn't itself proof
      // there's nothing left — see the "server caps below pageSize" test
      // below for why only an *empty* page is a safe-to-trust signal —
      // so this deliberately makes one extra round-trip rather than
      // guessing based on a short page alone.
      const total = 2500;
      final calls = <(int, int)>[];
      final result = await fetchAllPages((from, to) {
        calls.add((from, to));
        final remaining = total - from;
        if (remaining <= 0) return Future.value(const []);
        final count = remaining < (to - from + 1) ? remaining : (to - from + 1);
        return Future.value(rowsFrom(from, count));
      }, pageSize: 1000);

      expect(calls, [(0, 999), (1000, 1999), (2000, 2999), (2500, 3499)]);
      expect(result.length, total);
      expect(result.first['id'], '0');
      expect(result.last['id'], '${total - 1}');
    });

    test(
        "advances the offset by what a page actually returned, not the requested "
        'pageSize — safe even if the server caps a page below what was asked for',
        () async {
      // The server always caps at 100 rows, even though every call here
      // asks for up to 1000 — comparing a page's length to the
      // *requested* pageSize would wrongly treat every single page as
      // "the last one" and silently drop everything after the first 100.
      const total = 250;
      final calls = <(int, int)>[];
      final result = await fetchAllPages((from, to) {
        calls.add((from, to));
        final remaining = total - from;
        if (remaining <= 0) return Future.value(const []);
        final count = remaining < 100 ? remaining : 100;
        return Future.value(rowsFrom(from, count));
      }, pageSize: 1000);

      // offset advances by 100 each time (what actually came back), not
      // by the requested pageSize of 1000.
      expect(calls, [(0, 999), (100, 1099), (200, 1199), (250, 1249)]);
      expect(result.length, total);
      expect(result.map((r) => r['id']).toList(), List.generate(total, (i) => '$i'));
    });

    test('an empty archive makes exactly one call and returns nothing', () async {
      var callCount = 0;
      final result = await fetchAllPages((from, to) {
        callCount++;
        return Future.value(const []);
      });

      expect(callCount, 1);
      expect(result, isEmpty);
    });
  });
}
