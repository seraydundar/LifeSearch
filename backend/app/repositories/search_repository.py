"""Calls the `match_chunks` RPC (infra/supabase/migrations/0004_search.sql)
over PostgREST, scoped by the caller's own JWT — same pattern as
`items_repository.py`. No service_role key; `auth.uid()` inside the SQL
function is what actually scopes results to this user.
"""

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

    async def match_chunks(
        self, query_embedding: list[float], *, match_count: int = 40
    ) -> list[dict[str, Any]]:
        async with httpx.AsyncClient(timeout=20.0) as client:
            response = await client.post(
                f"{self._base_url}/rest/v1/rpc/match_chunks",
                headers=self._headers,
                json={
                    "query_embedding": format_embedding_literal(query_embedding),
                    "match_count": match_count,
                },
            )
            response.raise_for_status()
            return response.json()
