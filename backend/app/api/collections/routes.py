"""Smart Collections suggestion endpoint (requirements doc, section 129).

No mutation lives here — turning a suggestion into a real collection is a
plain Supabase insert the Flutter app does directly (see
`SupabaseCollectionRepository.createCollection`), the same way it creates
any other collection. This endpoint only ever reads and clusters.
"""

from fastapi import APIRouter, Depends

from ...core.config import get_settings
from ...core.security import CurrentUser, get_current_user
from ...repositories.search_repository import SearchRepository
from ...schemas.collections import SuggestCollectionsResponse, SuggestedCollection, SuggestedItem
from ...services.ai_provider import get_ai_provider
from ...services.collection_suggestion_service import suggest_collections

router = APIRouter(prefix="/collections", tags=["collections"])


@router.post("/suggest", response_model=SuggestCollectionsResponse)
async def suggest_endpoint(
    user: CurrentUser = Depends(get_current_user),
) -> SuggestCollectionsResponse:
    repo = SearchRepository(user.access_token)

    # Unlike /search/ and /ai/ask, a missing/broken AI provider doesn't
    # 503 here — clustering needs no provider at all, and naming just
    # falls back to a plainer name (see collection_suggestion_service).
    try:
        provider = get_ai_provider(get_settings())
    except (RuntimeError, NotImplementedError, ValueError):
        provider = None

    suggestions = await suggest_collections(repo, provider)

    return SuggestCollectionsResponse(
        suggestions=[
            SuggestedCollection(
                suggested_name=s["suggested_name"],
                items=[SuggestedItem(**item) for item in s["items"]],
            )
            for s in suggestions
        ]
    )
