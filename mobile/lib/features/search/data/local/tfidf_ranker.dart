import 'dart:math' as math;

/// Fully on-device TF-IDF + cosine-similarity relevance ranking — the
/// "tam offline semantic search" item from the audit (Faz 11, madde 6b,
/// see docs/roadmap.md).
///
/// **What this is not**: a neural embedding. It cannot match synonyms
/// or paraphrases — a query for "araba" will not match a document that
/// only says "otomobil". A real semantic match like that needs a
/// trained embedding model, which would mean bundling a multi-hundred-
/// megabyte model file and a native inference plugin into the app —
/// something that can't be verified end-to-end without a real device,
/// so it was deliberately not done here (see docs/roadmap.md, Faz 11
/// madde 6b for the trade-off this chose instead).
///
/// **What this fixes over plain substring search**
/// (`LocalSearchDataSource`'s previous behaviour): results are ranked
/// by how much of the query's vocabulary they actually contain, not
/// just "newest first" — and a multi-word query matches a document
/// even when its words land in different fields or a different order
/// ("kahve" in the title, "dükkanı" in the note body) — a plain
/// substring search can never do that, since it looks for the whole
/// query as one contiguous run of characters.
///
/// Deliberately a from-scratch ~50-line implementation, not a package:
/// the corpus here is one user's local item cache (realistically
/// hundreds to a few thousand rows), rebuilt fresh on every search — an
/// inverted index or a BM25 library would be solving a scale problem
/// this app doesn't have.
class TfidfDocument {
  const TfidfDocument({required this.id, required this.text});

  final String id;
  final String text;
}

/// Ranks [documents] against [query], highest cosine similarity first.
/// A document that shares no vocabulary with the query at all (cosine
/// similarity of exactly 0) is left out entirely — same "no match, not
/// just a low-ranked match" contract the old substring search had.
List<MapEntry<String, double>> rankByTfidf({
  required String query,
  required List<TfidfDocument> documents,
}) {
  final queryTokens = tokenize(query);
  if (queryTokens.isEmpty || documents.isEmpty) return const [];

  final tokensByDocId = <String, List<String>>{};
  final documentFrequency = <String, int>{}; // term -> how many docs contain it
  for (final doc in documents) {
    final tokens = tokenize(doc.text);
    tokensByDocId[doc.id] = tokens;
    for (final term in tokens.toSet()) {
      documentFrequency[term] = (documentFrequency[term] ?? 0) + 1;
    }
  }

  final documentCount = documents.length;
  // Smoothed idf: a term in every single document still gets a small
  // positive weight (1) rather than 0 — a query that's only common
  // words should still return *something*, just ranked lower than a
  // query containing rarer, more distinctive terms.
  double idf(String term) {
    final df = documentFrequency[term] ?? 0;
    if (df == 0) return 0; // never appears in the corpus at all
    return math.log(documentCount / df) + 1;
  }

  Map<String, double> vectorize(List<String> tokens) {
    final counts = <String, int>{};
    for (final token in tokens) {
      counts[token] = (counts[token] ?? 0) + 1;
    }
    final vector = <String, double>{};
    for (final entry in counts.entries) {
      // Log-scaled term frequency — a term appearing 10x in one field
      // shouldn't dominate 10x as much as one appearing once.
      final tf = 1 + math.log(entry.value);
      final weight = tf * idf(entry.key);
      if (weight > 0) vector[entry.key] = weight;
    }
    return vector;
  }

  double cosineSimilarity(Map<String, double> a, Map<String, double> b) {
    double dot = 0;
    for (final entry in a.entries) {
      final other = b[entry.key];
      if (other != null) dot += entry.value * other;
    }
    if (dot == 0) return 0;
    final normA = math.sqrt(a.values.fold(0.0, (sum, v) => sum + v * v));
    final normB = math.sqrt(b.values.fold(0.0, (sum, v) => sum + v * v));
    if (normA == 0 || normB == 0) return 0;
    return dot / (normA * normB);
  }

  final queryVector = vectorize(queryTokens);
  final scored = <MapEntry<String, double>>[];
  for (final doc in documents) {
    final score = cosineSimilarity(queryVector, vectorize(tokensByDocId[doc.id]!));
    if (score > 0) scored.add(MapEntry(doc.id, score));
  }
  scored.sort((a, b) => b.value.compareTo(a.value));
  return scored;
}

/// Lowercases and splits on anything that isn't a Unicode letter/digit
/// (so Turkish characters like "ı"/"ş"/"ğ" stay part of a word instead
/// of being treated as delimiters, unlike plain ASCII `\w`).
List<String> tokenize(String text) {
  return text
      .toLowerCase()
      .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
      .where((token) => token.isNotEmpty)
      .toList();
}
