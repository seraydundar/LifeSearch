"""Calls the search-related RPCs (infra/supabase/migrations/0004_search.sql,
0006_hybrid_and_related.sql) over PostgREST, scoped by the caller's own
JWT — same pattern as `items_repository.py`. No service_role key;
`auth.uid()` inside each SQL function is what actually scopes results to
this user.
"""

from datetime import datetime
from typing import Any

import httpx

from ..core.config import get_settings
from ..services.embedding_service import format_embedding_literal


class SearchRepository:
    def __init__(self, access_token: str) -> None:
        settings = get_settings()
        self._base_url = settings.supabase_url.rstrip("/")
        self._headers = {
            "apikey": settings.supabase_anon_key,
            "Authorization": f"Bearer {access_token}",
            "Content-Type": "application/json",
        }

    async def match_chunks_hybrid(
        self,
        query_embedding: list[float],
        query_text: str,
        *,
        match_count: int = 40,
        item_types: list[str] | None = None,
        date_after: datetime | None = None,
        date_before: datetime | None = None,
    ) -> list[dict[str, Any]]:
        payload: dict[str, Any] = {
            "query_embedding": format_embedding_literal(query_embedding),
            "query_text": query_text,
            "match_count": match_count,
        }
        if item_types:
            payload["filter_types"] = item_types
        if date_after:
            payload["filter_after"] = date_after.isoformat()
        if date_before:
            payload["filter_before"] = date_before.isoformat()

        async with httpx.AsyncClient(timeout=20.0) as client:
            response = await client.post(
                f"{self._base_url}/rest/v1/rpc/match_chunks_hybrid",
                headers=self._headers,
                json=payload,
            )
            response.raise_for_status()
            return response.json()

    async def related_items(self, item_id: str, *, match_count: int = 12) -> list[dict[str, Any]]:
        async with httpx.AsyncClient(timeout=20.0) as client:
            response = await client.post(
                f"{self._base_url}/rest/v1/rpc/related_items",
                headers=self._headers,
                json={"source_item_id": item_id, "match_count": match_count},
            )
            response.raise_for_status()
            return response.json()

    async def item_similarity_pairs(
        self, *, similarity_threshold: float = 0.75, max_pairs: int = 500
    ) -> list[dict[str, Any]]:
        async with httpx.AsyncClient(timeout=20.0) as client:
            response = await client.post(
                f"{self._base_url}/rest/v1/rpc/item_similarity_pairs",
                headers=self._headers,
                json={"similarity_threshold": similarity_threshold, "max_pairs": max_pairs},
            )
            response.raise_for_status()
            return response.json()

    async def find_duplicate_candidate(
        self, item_id: str, *, similarity_threshold: float = 0.93
    ) -> dict[str, Any] | None:
        """At most one match — the pipeline only needs to know whether a
        near-identical item already exists (requirements doc, section 46),
        not a ranked list.
        """
        async with httpx.AsyncClient(timeout=20.0) as client:
            response = await client.post(
                f"{self._base_url}/rest/v1/rpc/find_duplicate_candidate",
                headers=self._headers,
                json={"source_item_id": item_id, "similarity_threshold": similarity_threshold},
            )
            response.raise_for_status()
            rows = response.json()
            return rows[0] if rows else None
