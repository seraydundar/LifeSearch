"""LLM-based reranking of hybrid search results: RRF scores raw text match
only, with no notion of real relevance, so the LLM re-reads a shortlist and
reorders/drops candidates — this is also the only relevance threshold
anywhere in the search/RAG pipeline (no numeric score cutoff exists). Best
effort: any failure falls back to the caller's original order.
"""

import re
from typing import Any

from .ai_provider import AIProvider

# Bounds prompt cost regardless of how large a caller's `limit` is.
_MAX_CANDIDATES = 30
_MAX_SNIPPET_CHARS = 300

_NONE_RELEVANT = "yok"
# Only a clean number list or the none-relevant sentinel counts as a real
# answer; anything else (prose, embedded numbers) is treated as a misfire.
_CLEAN_LIST_RE = re.compile(r"^\d+(\s*,\s*\d+)*$")


async def rerank_matches(
    query: str,
    matches: list[dict[str, Any]],
    provider: AIProvider,
    *,
    limit: int,
) -> list[dict[str, Any]]:
    """Reorders `matches` (already deduped to one candidate per item) by
    asking the LLM to rank them against `query`, then returns the top
    `limit`. Expects a shortlist wider than `limit`, not an already-cut list.
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
    """Parses "3,1,4" (1-based) into 0-based indices to keep, in order; an
    index the model omits is treated as rejected, not forgotten. Returns `[]`
    for the "YOK" sentinel, `None` if the response isn't a clean number list.
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
