"""Semantic search endpoint. Synchronous (not a background task, unlike
/ai/process-item) — the mobile app is waiting on this one for a result to
show.
"""

from fastapi import APIRouter, Depends, HTTPException, status

from ...core.config import get_settings
from ...core.security import CurrentUser, get_current_user
from ...repositories.search_repository import SearchRepository
from ...schemas.search import SearchRequest, SearchResponse, SearchResult
from ...services.ai_provider import get_ai_provider
from ...services.search_service import semantic_search

router = APIRouter(prefix="/search", tags=["search"])


@router.post("/", response_model=SearchResponse)
async def search_endpoint(
    body: SearchRequest,
    user: CurrentUser = Depends(get_current_user),
) -> SearchResponse:
    try:
        provider = get_ai_provider(get_settings())
    except (RuntimeError, NotImplementedError, ValueError) as error:
        # A config problem (no key, unimplemented provider) is a service
        # outage from the client's point of view, not "no results" — 503
        # says so plainly instead of returning an empty result list.
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"Search is unavailable: {error}",
        ) from error

    repo = SearchRepository(user.access_token)
    matches = await semantic_search(body.query, repo, provider, limit=body.limit)

    return SearchResponse(
        query=body.query,
        results=[
            SearchResult(
                item_id=m["item_id"],
                item_type=m["item_type"],
                item_title=m.get("item_title"),
                snippet=m["content"],
                similarity=m["similarity"],
            )
            for m in matches
        ],
    )
