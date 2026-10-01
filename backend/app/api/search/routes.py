"""Search endpoints. Synchronous (unlike /ai/process-item): the mobile app waits on the result."""

from fastapi import APIRouter, Depends, HTTPException, status

from ...core.config import get_settings
from ...core.rate_limit import require_search_rate_limit
from ...core.security import CurrentUser, get_current_user
from ...repositories.search_repository import SearchRepository
from ...schemas.search import (
    RelatedRequest,
    RelatedResponse,
    SearchRequest,
    SearchResponse,
    SearchResult,
)
from ...services.ai_provider import get_ai_provider
from ...services.query_parser import parse_query
from ...services.search_service import find_related_items, semantic_search

router = APIRouter(prefix="/search", tags=["search"])


def _require_provider():
    try:
        return get_ai_provider(get_settings())
    except (RuntimeError, NotImplementedError, ValueError) as error:
        # Config problem = service outage to the client, not "no results".
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"Search is unavailable: {error}",
        ) from error


def _to_result(match: dict) -> SearchResult:
    return SearchResult(
        item_id=match["item_id"],
        item_type=match["item_type"],
        item_title=match.get("item_title"),
        snippet=match["content"],
        similarity=match["similarity"],
    )


@router.post("/", response_model=SearchResponse)
async def search_endpoint(
    body: SearchRequest,
    user: CurrentUser = Depends(require_search_rate_limit),
) -> SearchResponse:
    provider = _require_provider()
    repo = SearchRepository(user.access_token)

    # Pulls type/date filters out of the query text; explicit client filters win.
    parsed = parse_query(body.query, timezone_offset_minutes=body.timezone_offset_minutes)
    item_types = body.item_types or parsed.item_types
    date_from = body.date_from or parsed.date_from
    # Parser's date_to must apply too, or "dün" matches yesterday onward instead of just that day.
    date_to = body.date_to or parsed.date_to

    matches = await semantic_search(
        parsed.cleaned_query,
        repo,
        provider,
        limit=body.limit,
        item_types=item_types,
        date_after=date_from,
        date_before=date_to,
        include_private=body.include_private,
    )

    return SearchResponse(query=body.query, results=[_to_result(m) for m in matches])


@router.post("/related", response_model=RelatedResponse)
async def related_endpoint(
    body: RelatedRequest,
    user: CurrentUser = Depends(get_current_user),
) -> RelatedResponse:
    """Similarity against the source item's own content; no query text or AI provider call,
    so it's not behind require_search_rate_limit."""
    repo = SearchRepository(user.access_token)
    matches = await find_related_items(
        body.item_id, repo, limit=body.limit, include_private=body.include_private
    )

    return RelatedResponse(item_id=body.item_id, results=[_to_result(m) for m in matches])
