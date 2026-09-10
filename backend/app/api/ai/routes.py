"""AI processing endpoints.

The mobile app calls `POST /ai/process-item` right after a note/PDF
successfully syncs to Supabase (see the Flutter side's `AiProcessingTrigger`,
called from `SyncService`). Nothing here talks back to Supabase using an
admin key — it reuses the caller's own session token, so RLS applies
exactly as it would if the client made the request itself.
"""

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, status

from ...core.config import get_settings
from ...core.rate_limit import require_ai_rate_limit
from ...core.security import CurrentUser
from ...repositories.items_repository import SupabaseRestRepository
from ...repositories.search_repository import SearchRepository
from ...schemas.ai import AskRequest, AskResponse, ProcessItemRequest, ProcessItemResponse
from ...schemas.search import SearchResult
from ...services.ai_provider import get_ai_provider
from ...services.processing_pipeline import process_item
from ...services.rag_service import answer_question

router = APIRouter(prefix="/ai", tags=["ai"])


@router.post("/process-item", response_model=ProcessItemResponse, status_code=202)
async def process_item_endpoint(
    body: ProcessItemRequest,
    background_tasks: BackgroundTasks,
    user: CurrentUser = Depends(require_ai_rate_limit),
) -> ProcessItemResponse:
    repo = SupabaseRestRepository(user.access_token)
    # Returns immediately; the item's `processing_status` (and the
    # matching `processing_jobs` row) is what actually reports progress —
    # including a bad AI_PROVIDER config, resolved lazily inside the task.
    background_tasks.add_task(
        process_item,
        body.item_id,
        repo,
        lambda: get_ai_provider(get_settings()),
        lambda: SearchRepository(user.access_token),
        user_id=user.id,
    )
    return ProcessItemResponse(status="accepted", item_id=body.item_id)


@router.post("/ask", response_model=AskResponse)
async def ask_endpoint(
    body: AskRequest,
    user: CurrentUser = Depends(require_ai_rate_limit),
) -> AskResponse:
    """RAG chat (requirements doc, section 23): answers only from the
    user's own archive, always with the sources it used.
    """
    try:
        provider = get_ai_provider(get_settings())
    except (RuntimeError, NotImplementedError, ValueError) as error:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"Ask AI is unavailable: {error}",
        ) from error

    repo = SearchRepository(user.access_token)
    result = await answer_question(body.question, repo, provider, limit=body.limit)

    return AskResponse(
        question=body.question,
        answer=result["answer"],
        sources=[
            SearchResult(
                item_id=m["item_id"],
                item_type=m["item_type"],
                item_title=m.get("item_title"),
                snippet=m["content"],
                similarity=m["similarity"],
            )
            for m in result["sources"]
        ],
    )
