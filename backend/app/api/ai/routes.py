"""AI processing endpoints.

The mobile app calls `POST /ai/process-item` right after a note/PDF
successfully syncs to Supabase (see the Flutter side's `AiProcessingTrigger`,
called from `SyncService`). Nothing here talks back to Supabase using an
admin key — it reuses the caller's own session token, so RLS applies
exactly as it would if the client made the request itself.
"""

from fastapi import APIRouter, BackgroundTasks, Depends

from ...core.config import get_settings
from ...core.security import CurrentUser, get_current_user
from ...repositories.items_repository import SupabaseRestRepository
from ...schemas.ai import ProcessItemRequest, ProcessItemResponse
from ...services.ai_provider import get_ai_provider
from ...services.processing_pipeline import process_item

router = APIRouter(prefix="/ai", tags=["ai"])


@router.post("/process-item", response_model=ProcessItemResponse, status_code=202)
async def process_item_endpoint(
    body: ProcessItemRequest,
    background_tasks: BackgroundTasks,
    user: CurrentUser = Depends(get_current_user),
) -> ProcessItemResponse:
    repo = SupabaseRestRepository(user.access_token)
    # Returns immediately; the item's `processing_status` (and the
    # matching `processing_jobs` row) is what actually reports progress —
    # including a bad AI_PROVIDER config, resolved lazily inside the task.
    background_tasks.add_task(
        process_item, body.item_id, repo, lambda: get_ai_provider(get_settings())
    )
    return ProcessItemResponse(status="accepted", item_id=body.item_id)
