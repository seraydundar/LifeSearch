import 'dart:math' as math;

/// Not a neural embedding — no synonym/paraphrase matching, only shared vocabulary.
/// From-scratch rather than a package since the corpus (one user's local cache) is small.
class TfidfDocument {
  const TfidfDocument({required this.id, required this.text});

  final String id;
  final String text;
}

/// Ranks [documents] against [query], highest cosine similarity first.
/// A document with zero shared vocabulary is left out entirely, not just ranked low.
List<MapEntry<String, double>> rankByTfidf({
  required String query,
  required List<TfidfDocument> documents,
}) {
  final queryTokens = tokenize(query);
  if (queryTokens.isEmpty || documents.isEmpty) return const [];

  final tokensByDocId = <String, List<String>>{};
  final documentFrequency = <String, int>{};
  for (final doc in documents) {
    final tokens = tokenize(doc.text);
    tokensByDocId[doc.id] = tokens;
    for (final term in tokens.toSet()) {
      documentFrequency[term] = (documentFrequency[term] ?? 0) + 1;
    }
  }

  final documentCount = documents.length;
  // Smoothed: a term in every document still gets weight 1 instead of 0.
  double idf(String term) {
    final df = documentFrequency[term] ?? 0;
    if (df == 0) return 0;
    return math.log(documentCount / df) + 1;
  }

  Map<String, double> vectorize(List<String> tokens) {
    final counts = <String, int>{};
    for (final token in tokens) {
      counts[token] = (counts[token] ?? 0) + 1;
    }
    final vector = <String, double>{};
    for (final entry in counts.entries) {
      // Log-scaled: a term appearing 10x shouldn't dominate 10x as much.
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

/// Splits on non-Unicode-letter/digit so Turkish characters like "ı"/"ş"/"ğ" stay in-word.
List<String> tokenize(String text) {
  return text
      .toLowerCase()
      .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
      .where((token) => token.isNotEmpty)
      .toList();
}
