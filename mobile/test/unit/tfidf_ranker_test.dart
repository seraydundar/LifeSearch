import 'package:flutter_test/flutter_test.dart';
import 'package:lifesearch/features/search/data/local/tfidf_ranker.dart';

void main() {
  group('tokenize', () {
    test('lowercases and splits on non-letter/digit characters', () {
      expect(tokenize('Docker, Container! (v2.0)'), ['docker', 'container', 'v2', '0']);
    });

    test('keeps Turkish letters as part of a word instead of splitting on them', () {
      expect(tokenize('Kahve dükkanı'), ['kahve', 'dükkanı']);
    });

    test('an empty or whitespace-only string tokenizes to nothing', () {
      expect(tokenize('   '), isEmpty);
    });
  });

  group('rankByTfidf', () {
    test('a document sharing no vocabulary with the query is left out entirely', () {
      final result = rankByTfidf(
        query: 'docker',
        documents: const [TfidfDocument(id: 'a', text: 'kubernetes notes')],
      );

      expect(result, isEmpty);
    });

    test('an empty query or an empty corpus ranks nothing', () {
      expect(rankByTfidf(query: '', documents: const [TfidfDocument(id: 'a', text: 'docker')]),
          isEmpty);
      expect(rankByTfidf(query: 'docker', documents: const []), isEmpty);
    });

    test('matches a multi-word query even when its words land in different documents fields '
        'combined into one — i.e. not requiring one contiguous substring', () {
      final result = rankByTfidf(
        query: 'kahve dükkanı',
        documents: const [
          // "kahve" and "dükkanı" never appear next to each other.
          TfidfDocument(id: 'a', text: 'kahve fasulyesi alışveriş listesi dükkanı ziyaret et'),
          TfidfDocument(id: 'b', text: 'tamamen ilgisiz bir not'),
        ],
      );

      expect(result.map((e) => e.key), ['a']);
    });

    test('ranks a document containing more of the query vocabulary higher', () {
      final result = rankByTfidf(
        query: 'docker container image',
        documents: const [
          TfidfDocument(id: 'only-docker', text: 'docker notes'),
          TfidfDocument(
            id: 'all-three',
            text: 'docker container image tutorial: building a docker image from a container',
          ),
        ],
      );

      expect(result.map((e) => e.key).first, 'all-three');
    });

    test('a rarer shared term outweighs a very common one repeated many times', () {
      // "the" appears in every document (near-zero idf); "postgresql"
      // appears in exactly one — that one document should win even
      // though the other repeats the common word a lot.
      final result = rankByTfidf(
        query: 'postgresql the',
        documents: const [
          TfidfDocument(id: 'has-postgresql', text: 'the the the postgresql setup notes'),
          TfidfDocument(id: 'only-common-word', text: 'the the the the the the'),
        ],
      );

      expect(result.map((e) => e.key).first, 'has-postgresql');
    });

    test('results are sorted by similarity, highest first', () {
      final result = rankByTfidf(
        query: 'docker',
        documents: const [
          TfidfDocument(id: 'weak', text: 'docker mentioned once among many other unrelated words here'),
          TfidfDocument(id: 'strong', text: 'docker'),
        ],
      );

      for (var i = 1; i < result.length; i++) {
        expect(result[i - 1].value, greaterThanOrEqualTo(result[i].value));
      }
    });
  });
}
