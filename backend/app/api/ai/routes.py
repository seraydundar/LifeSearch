"""AI processing endpoints. Uses the caller's own session token (no admin key), so RLS applies."""

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
    # Job row is created before returning 202, not inside the background task,
    # so a crash before the task starts still leaves a row for job_recovery.py to find.
    try:
        job_id = await repo.create_job(body.item_id, job_type="chunk_and_embed")
    except Exception as error:
        await repo.aclose()
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"Could not start processing: {error}",
        ) from error

    # Progress (incl. a bad AI_PROVIDER config) is reported via processing_status, not here.
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
    """Answers only from the user's own archive, always with sources."""
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
    """Re-embeds stale chunks after an AI_PROVIDER switch (re-embed only, not a full reprocess).
    stale_item_count is counted synchronously; the re-embedding itself runs in the background.
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
