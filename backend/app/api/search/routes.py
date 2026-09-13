"""Search endpoints. Synchronous (not background tasks, unlike
/ai/process-item) — the mobile app is waiting on these for a result.
"""

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
        # A config problem (no key, unimplemented provider) is a service
        # outage from the client's point of view, not "no results" — 503
        # says so plainly instead of returning an empty result list.
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

    # Natural-language filtering (requirements doc, section 22): pull a
    # type/date filter out of the query text itself, e.g. "geçen ay
    # baktığım PDF'ler". Anything the client already sent explicitly (the
    # Search tab's filter chips) wins — this only fills in the gaps.
    parsed = parse_query(body.query)
    item_types = body.item_types or parsed.item_types
    date_from = body.date_from or parsed.date_from
    # Previously always `body.date_to` — silently dropping the parser's
    # own upper bound (see query_parser.py's "geçen X" phrases) whenever
    # the client hadn't sent one of its own, so e.g. "dün" kept matching
    # everything from yesterday onward instead of yesterday alone.
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
    """Related items (requirements doc, section 47) — similarity against
    the source item's own content, no query text involved. Not behind
    `require_search_rate_limit`: unlike `/search/`, this never calls the
    AI provider (it reuses an already-stored chunk embedding as the
    comparison vector — see `find_related_items`), so it doesn't carry
    the per-call cost the rate limit exists to bound.
    """
    repo = SearchRepository(user.access_token)
    matches = await find_related_items(
        body.item_id, repo, limit=body.limit, include_private=body.include_private
    )

    return RelatedResponse(item_id=body.item_id, results=[_to_result(m) for m in matches])
