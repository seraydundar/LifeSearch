"""LLM-based reranking of hybrid search results (requirements doc,
section 65's "Reranking" — explicitly deferred as "ileri aşama" until
now; `search_service.py` used to say so in its own module docstring).

RRF (the `match_chunks_hybrid` SQL RPC + `search_service._dedupe_best_per_item`)
is fast and cheap, but it only ever sees a chunk's raw text scored
against the query by embedding distance and keyword frequency — it has
no notion of *why* something matches. A short passage that happens to
repeat the query's words can outrank a longer, more genuinely relevant
one on ts_rank/similarity grounds alone. This asks the LLM itself, which
actually reads each candidate, to reorder a modest shortlist by real
relevance — the same trade a dedicated cross-encoder reranker would make
in a non-LLM-backed stack, but reusing the same `generate_text` the rest
of this service already depends on rather than adding a second, different
kind of model (rule 4, "gereksiz abstraction oluşturma").

Best-effort by design — same contract as `tagging_service`/
`entity_extraction_service`: any failure (a provider error, a response
that doesn't parse into anything usable) falls back to the order the
caller already had. Reranking can only reorder or narrow candidates
`search_service` already found; it must never be the reason search
itself breaks or returns nothing.
"""

from typing import Any

from .ai_provider import AIProvider

# Keeps the prompt (and the cost/latency of the extra completion call)
# bounded even if a caller asks for a very large `limit` — past this
# many candidates, reordering stops being worth the extra tokens.
_MAX_CANDIDATES = 30
_MAX_SNIPPET_CHARS = 300


async def rerank_matches(
    query: str,
    matches: list[dict[str, Any]],
    provider: AIProvider,
    *,
    limit: int,
) -> list[dict[str, Any]]:
    """Reorders `matches` (already deduped to one candidate per item, in
    the caller's own best-guess — RRF — order) by asking the LLM to rank
    them against `query`, then returns the top `limit`.

    `matches` should already be a modest shortlist, not the full
    over-fetched candidate pool — `semantic_search` widens its dedupe
    limit for exactly this reason, so there's something for reranking to
    actually change instead of just reordering a list already cut down
    to `limit` by RRF alone.
    """
    candidates = matches[:_MAX_CANDIDATES]
    if len(candidates) <= 1:
        return candidates[:limit]

    listing = "\n".join(
        f"{i + 1}. ({m['item_type']}, {m.get('item_title') or 'Untitled'}): "
        f"{m['content'][:_MAX_SNIPPET_CHARS]}"
        for i, m in enumerate(candidates)
    )
    prompt = (
        f"Sorgu: {query}\n\nAdaylar:\n{listing}\n\n"
        "Yukarıdaki adayları sorguyla EN alakalıdan EN az alakalıya doğru "
        "sırala. Sadece numaraları virgülle ayırarak yaz (ör. 3,1,4,2), "
        "başka hiçbir şey yazma. Her numara tam olarak bir kez geçmeli."
    )

    try:
        response = await provider.generate_text(prompt)
    except Exception:
        return candidates[:limit]

    order = _parse_order(response, count=len(candidates))
    if order is None:
        return candidates[:limit]

    return [candidates[i] for i in order][:limit]


def _parse_order(response: str, *, count: int) -> list[int] | None:
    """Parses "3,1,4,2" (1-based, as asked in the prompt) into a list of
    0-based indices. Delimiter-tolerant rather than requiring strict
    JSON/CSV — same reasoning as `tagging_service`/`entity_extraction_service`:
    one stray character in the model's response shouldn't discard the
    whole ranking.

    Returns `None` (meaning "unusable, fall back") if the response
    mentions fewer than half the candidates — a response that's mostly
    prose instead of a ranking is more likely a misfire than a real
    partial ranking. Any index outside `range(count)`, or a repeat, is
    silently dropped rather than treated as a hard parse failure.
    """
    seen: list[int] = []
    for token in response.replace("\n", ",").split(","):
        token = token.strip()
        if not token.isdigit():
            continue
        index = int(token) - 1
        if 0 <= index < count and index not in seen:
            seen.append(index)

    if len(seen) < max(1, count // 2):
        return None

    # Anything the model never mentioned keeps its original relative
    # order, appended after everything it did rank — a partial ranking
    # is still strictly better than discarding candidates it simply
    # didn't call out.
    seen.extend(i for i in range(count) if i not in seen)
    return seen
