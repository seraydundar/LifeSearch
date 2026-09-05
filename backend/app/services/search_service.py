"""Semantic + hybrid search over items/chunks via pgvector (requirements
doc, sections 19-21) and related-items lookup (section 47). Reranking and
natural-language filter extraction (sections 20, 22) stay out of scope —
noted as "ileri aşama" in the doc itself.
"""

from datetime import datetime
from typing import Any

from ..repositories.search_repository import SearchRepository
from .ai_provider import AIProvider


def _dedupe_best_per_item(matches: list[dict[str, Any]], *, limit: int) -> list[dict[str, Any]]:
    """Several chunks can belong to the same item — keep only each item's
    best-scoring chunk, ranked highest first.
    """
    best_per_item: dict[str, dict[str, Any]] = {}
    for match in matches:
        item_id = match["item_id"]
        if item_id not in best_per_item or match["score"] > best_per_item[item_id]["score"]:
            best_per_item[item_id] = match

    ranked = sorted(best_per_item.values(), key=lambda m: m["score"], reverse=True)
    return ranked[:limit]


async def semantic_search(
    query: str,
    repo: SearchRepository,
    provider: AIProvider,
    *,
    limit: int = 10,
    item_types: list[str] | None = None,
    date_after: datetime | None = None,
    date_before: datetime | None = None,
) -> list[dict[str, Any]]:
    query_embedding = await provider.generate_embedding(query)

    # Over-fetch chunks since several can belong to the same item — dedupe
    # down to one (its best-matching) chunk per item below.
    matches = await repo.match_chunks_hybrid(
        query_embedding,
        query,
        match_count=limit * 4,
        item_types=item_types,
        date_after=date_after,
        date_before=date_before,
    )
    return _dedupe_best_per_item(matches, limit=limit)


async def find_related_items(
    item_id: str,
    repo: SearchRepository,
    *,
    limit: int = 6,
) -> list[dict[str, Any]]:
    matches = await repo.related_items(item_id, match_count=limit * 3)
    # related_items() has no keyword/hybrid score, only cosine similarity —
    # reuse the same dedupe shape by aliasing it as "score".
    for match in matches:
        match.setdefault("score", match["similarity"])
    return _dedupe_best_per_item(matches, limit=limit)
