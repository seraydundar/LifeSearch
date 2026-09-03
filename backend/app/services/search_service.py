"""Semantic search over items/chunks via pgvector (requirements doc,
section 19). Hybrid search (keyword + metadata filters on top of this)
and result reranking are Phase 9 — this is vector similarity only.
"""

from typing import Any

from ..repositories.search_repository import SearchRepository
from .ai_provider import AIProvider


async def semantic_search(
    query: str,
    repo: SearchRepository,
    provider: AIProvider,
    *,
    limit: int = 10,
) -> list[dict[str, Any]]:
    query_embedding = await provider.generate_embedding(query)

    # Over-fetch chunks since several can belong to the same item — dedupe
    # down to one (its best-matching) chunk per item below.
    matches = await repo.match_chunks(query_embedding, match_count=limit * 4)

    best_per_item: dict[str, dict[str, Any]] = {}
    for match in matches:
        item_id = match["item_id"]
        if (
            item_id not in best_per_item
            or match["similarity"] > best_per_item[item_id]["similarity"]
        ):
            best_per_item[item_id] = match

    ranked = sorted(best_per_item.values(), key=lambda m: m["similarity"], reverse=True)
    return ranked[:limit]
