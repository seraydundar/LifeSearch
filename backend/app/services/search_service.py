"""Semantic + hybrid search, reranking, and related-items lookup over
items/chunks via pgvector. Filter extraction happens one layer up in
`query_parser.py` — this module only sees already-resolved filters.
"""

from datetime import datetime
from typing import Any

from ..repositories.search_repository import SearchRepository
from .ai_provider import AIProvider
from .reranking_service import rerank_matches


def _dedupe_best_per_item(matches: list[dict[str, Any]], *, limit: int) -> list[dict[str, Any]]:
    """Keeps each item's best-scoring chunk only, ranked highest first."""
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
    rerank: bool = True,
    include_private: bool = False,
) -> list[dict[str, Any]]:
    query_embedding = await provider.generate_embedding(query)

    # Over-fetch since several chunks can belong to the same item; deduped below.
    matches = await repo.match_chunks_hybrid(
        query_embedding,
        query,
        match_count=limit * 4,
        item_types=item_types,
        date_after=date_after,
        date_before=date_before,
        include_private=include_private,
        # Never compare against a chunk embedded by a different provider.
        embedding_provider=provider.provider_name,
        embedding_model=provider.embedding_model,
    )
    # Keep a shortlist wider than `limit` so rerank_matches has something to
    # actually reorder, instead of just a pre-cut list.
    shortlist = _dedupe_best_per_item(matches, limit=min(len(matches), limit * 2))

    if not rerank:
        return shortlist[:limit]
    return await rerank_matches(query, shortlist, provider, limit=limit)


async def find_related_items(
    item_id: str,
    repo: SearchRepository,
    *,
    limit: int = 6,
    include_private: bool = False,
) -> list[dict[str, Any]]:
    matches = await repo.related_items(
        item_id, match_count=limit * 3, include_private=include_private
    )
    # related_items() only has cosine similarity; alias it as "score" to reuse the dedupe.
    for match in matches:
        match.setdefault("score", match["similarity"])
    return _dedupe_best_per_item(matches, limit=limit)
