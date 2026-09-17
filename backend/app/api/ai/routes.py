"""AI processing endpoints.

The mobile app calls `POST /ai/process-item` right after a note/PDF
successfully syncs to Supabase (see the Flutter side's `AiProcessingTrigger`,
called from `SyncService`). Nothing here talks back to Supabase using an
admin key — it reuses the caller's own session token, so RLS applies
exactly as it would if the client made the request itself.
"""

import logging

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, status

from ...core.config import get_settings
from ...core.rate_limit import require_ai_rate_limit
from ...core.security import CurrentUser
from ...repositories.items_repository import SupabaseRestRepository
from ...repositories.search_repository import SearchRepository
from ...schemas.ai import (
    AskRequest,
    AskResponse,
    ProcessItemRequest,
    ProcessItemResponse,
    ReprocessStaleEmbeddingsResponse,
)
from ...schemas.search import SearchResult
from ...services.ai_provider import AIProvider, get_ai_provider
from ...services.processing_pipeline import process_item
from ...services.rag_service import answer_question
from ...services.reembedding_service import reembed_stale_items

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/ai", tags=["ai"])


@router.post("/process-item", response_model=ProcessItemResponse, status_code=202)
async def process_item_endpoint(
    body: ProcessItemRequest,
    background_tasks: BackgroundTasks,
    user: CurrentUser = Depends(require_ai_rate_limit),
) -> ProcessItemResponse:
    repo = SupabaseRestRepository(user.access_token)
    # Created *before* "202 accepted" is returned, not as this task's own
    # first line (P1-05, docs/requirements-audit-2026-09-13.md):
    # `BackgroundTasks` only start running after the response is already
    # on the wire, so a process death in that gap used to leave no trace
    # at all — no row for `job_recovery.py`'s startup sweep to find, and
    # a `create_job` failure itself never reached the normal failed/
    # status flow (it was outside `process_item`'s own try/except).
    # Raising here instead surfaces it as a normal failed request, which
    # the mobile client already retries (see `SyncService._triggerAi`'s
    # queued `trigger_ai` retry).
    try:
        job_id = await repo.create_job(body.item_id, job_type="chunk_and_embed")
    except Exception as error:
        await repo.aclose()
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"Could not start processing: {error}",
        ) from error

    # Returns immediately; the item's `processing_status` (and the
    # matching `processing_jobs` row) is what actually reports progress —
    # including a bad AI_PROVIDER config, resolved lazily inside the task.
    background_tasks.add_task(
        process_item,
        body.item_id,
        job_id,
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
    history = [{"role": turn.role, "text": turn.text} for turn in body.history]
    result = await answer_question(
        body.question, repo, provider, limit=body.limit, history=history
    )

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


@router.post(
    "/reprocess-stale-embeddings",
    response_model=ReprocessStaleEmbeddingsResponse,
    status_code=202,
)
async def reprocess_stale_embeddings_endpoint(
    background_tasks: BackgroundTasks,
    user: CurrentUser = Depends(require_ai_rate_limit),
) -> ReprocessStaleEmbeddingsResponse:
    """User-triggered fix for a provider/model switch (P3, docs/
    requirements-audit-2026-09-13.md) — a Settings button for "I just
    changed AI_PROVIDER, some of my search results might be wrong now."
    Re-embeds only; see `reembedding_service.py`'s own docstring for why
    that's a deliberately narrower scope than a full reprocess.

    `stale_item_count` is known synchronously (one quick query) even
    though the actual re-embedding happens in the background after this
    response is sent — same "202 now, work after" shape as
    `/process-item`, just without a `processing_status` the mobile app
    would need to poll (see `reembed_stale_items`'s docstring for why).
    """
    try:
        provider = get_ai_provider(get_settings())
    except (RuntimeError, NotImplementedError, ValueError) as error:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"Re-embedding is unavailable: {error}",
        ) from error

    repo = SupabaseRestRepository(user.access_token)
    try:
        stale_item_ids = await repo.find_stale_chunk_item_ids(
            provider.provider_name, provider.embedding_model
        )
    except Exception as error:
        await repo.aclose()
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"Could not check for stale embeddings: {error}",
        ) from error

    background_tasks.add_task(_reembed_stale_and_close, repo, provider)
    return ReprocessStaleEmbeddingsResponse(
        status="accepted", stale_item_count=len(stale_item_ids)
    )


async def _reembed_stale_and_close(repo: SupabaseRestRepository, provider: AIProvider) -> None:
    try:
        count = await reembed_stale_items(repo, provider)
        logger.info("re-embedded stale chunks", extra={"item_count": count})
    finally:
        await repo.aclose()
