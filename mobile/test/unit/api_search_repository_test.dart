import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesearch/features/search/data/remote/api_search_repository.dart';
import 'package:lifesearch/features/search/domain/entities/search_filters.dart';

/// Builds an `ApiSearchRepository` whose Dio never actually reaches the
/// network — an interceptor captures the outgoing request body into
/// [captured] and rejects it before it's sent.
ApiSearchRepository _repoCapturingRequestBodyInto(Map<String, dynamic> captured) {
  final dio = Dio(BaseOptions(baseUrl: 'http://localhost'));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        captured.addAll(options.data as Map<String, dynamic>);
        handler.reject(DioException(requestOptions: options));
      },
    ),
  );
  return ApiSearchRepository(dio);
}

/// `search()` turns the interceptor's rejection into a thrown
/// `UnexpectedFailure` — every test here wants the request it built
/// ([captured]), not the (deliberately broken) result, so it calls
/// `search()` through this instead of awaiting it directly.
Future<void> _fireAndIgnoreTheExpectedFailure(Future<Object?> call) async {
  try {
    await call;
  } catch (_) {
    // Expected — see doc comment above.
  }
}

void main() {
  // P2-02 (docs/requirements-audit-2026-09-13.md): `SearchFilters.dateFrom`/
  // `dateTo` are local `DateTime`s (see search_tab.dart's date presets
  // and custom range picker) — Dart's `toIso8601String()` omits the
  // timezone offset for anything that isn't already UTC, so the backend
  // used to silently read a local midnight as if it were a UTC one.
  group('ApiSearchRepository.search date serialization', () {
    test('a local dateFrom is sent as its correct, self-describing UTC instant', () async {
      final captured = <String, dynamic>{};
      final repo = _repoCapturingRequestBodyInto(captured);
      final localMidnight = DateTime(2026, 1, 1); // local time, not UTC

      await _fireAndIgnoreTheExpectedFailure(
        repo.search('query', filters: SearchFilters(dateFrom: localMidnight)),
      );

      final sent = captured['date_from'] as String;
      expect(sent, endsWith('Z')); // self-describing UTC, not ambiguous
      expect(DateTime.parse(sent), localMidnight.toUtc());
    });

    test('dateTo is converted the same way', () async {
      final captured = <String, dynamic>{};
      final repo = _repoCapturingRequestBodyInto(captured);
      final localInstant = DateTime(2026, 1, 1, 23, 59, 59);

      await _fireAndIgnoreTheExpectedFailure(
        repo.search('query', filters: SearchFilters(dateTo: localInstant)),
      );

      final sent = captured['date_to'] as String;
      expect(sent, endsWith('Z'));
      expect(DateTime.parse(sent), localInstant.toUtc());
    });

    test("the request always includes the client's current timezone offset", () async {
      final captured = <String, dynamic>{};
      final repo = _repoCapturingRequestBodyInto(captured);

      await _fireAndIgnoreTheExpectedFailure(repo.search('query')); // no date filters at all

      expect(captured['timezone_offset_minutes'], DateTime.now().timeZoneOffset.inMinutes);
    });
  });
}
