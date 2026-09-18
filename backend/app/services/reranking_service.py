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
itself breaks.

P2-01 (docs/requirements-audit-2026-09-13.md): "narrow" used to be
theoretical — the LLM only ever reordered the full candidate list, so a
genuinely irrelevant candidate always survived into the final `limit`
results. The prompt now asks the model to actually drop candidates that
don't answer the query at all (or say `YOK` if none of them do), and
`_parse_order` no longer pads a partial ranking back up to the full
candidate count — an index the model didn't mention is excluded, not
"probably still relevant, just forgotten." This doubles as `semantic_
search`'s and `answer_question`'s (RAG) only relevance threshold: no
numeric similarity/score cutoff exists anywhere else in this pipeline.
"""

import re
from typing import Any

from .ai_provider import AIProvider

# Keeps the prompt (and the cost/latency of the extra completion call)
# bounded even if a caller asks for a very large `limit` — past this
# many candidates, reordering stops being worth the extra tokens.
_MAX_CANDIDATES = 30
_MAX_SNIPPET_CHARS = 300

_NONE_RELEVANT = "yok"
# The only two shapes we trust as a deliberate answer: the none-relevant
# sentinel, or a comma/newline-separated list of bare numbers. Anything
# else (prose, a number embedded in a sentence) reads as a misfire, not
# a genuine ranking — see _parse_order.
_CLEAN_LIST_RE = re.compile(r"^\d+(\s*,\s*\d+)*$")


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
        "Yukarıdaki adaylardan sorguyla GERÇEKTEN alakalı olanları EN "
        "alakalıdan EN az alakalıya doğru sırala. Sorguyla hiçbir ilgisi "
        "olmayan adayları listeye YAZMA. Sadece numaraları virgülle "
        "ayırarak yaz (ör. 3,1,4), başka hiçbir şey yazma. Hiçbir aday "
        "sorguyla alakalı değilse, sadece 'YOK' yaz."
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
    """Parses "3,1,4" (1-based, as asked in the prompt) into a list of
    0-based indices — the candidates to keep, in relevance order. An
    index the model never mentions is dropped, not appended: omission is
    now the model's way of rejecting a candidate as irrelevant (P2-01).

    Returns `[]` if the response is the explicit "nothing is relevant"
    sentinel (`YOK`). Returns `None` (meaning "unusable, fall back to
    the caller's original order") if the response isn't a clean
    comma-separated list of bare numbers — a reply mixed with prose (a
    number embedded in a sentence, an explanation) is more likely a
    misfire than a deliberate short list, regardless of how many
    candidates it does or doesn't mention. Whether it's a clean list is
    checked on the *whole* response — no digit-count heuristic, since a
    short but well-formed list (most candidates genuinely rejected) is
    just as trustworthy as a long one.
    """
    cleaned = response.strip()
    if cleaned.casefold() == _NONE_RELEVANT:
        return []

    normalized = cleaned.replace("\n", ",")
    if not _CLEAN_LIST_RE.match(normalized):
        return None

    seen: list[int] = []
    for token in normalized.split(","):
        index = int(token.strip()) - 1
        if 0 <= index < count and index not in seen:
            seen.append(index)

    return seen or None
