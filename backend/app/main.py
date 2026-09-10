"""LifeSearch AI Service — FastAPI entrypoint.

This service owns every AI-heavy operation (OCR, chunking, embeddings,
vector/hybrid search, RAG, vision, transcription). The Flutter app talks
to Supabase directly for plain CRUD + auth, and to this service for
anything that needs an AI provider — so provider API keys never live in
the mobile app.

Phase 4 wires up the AI processing pipeline (`/ai/process-item`). Auth,
items and search routers are still scaffolding — they land in later
phases (see docs/requirements.md).
"""

import logging
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.account.routes import router as account_router
from app.api.ai.routes import router as ai_router
from app.api.collections.routes import router as collections_router
from app.api.search.routes import router as search_router
from app.core.config import get_settings
from app.core.logging import configure_logging, request_logging_middleware
from app.repositories.items_repository import SupabaseRestRepository
from app.services.job_recovery import recover_orphaned_jobs

settings = get_settings()
configure_logging(debug=settings.debug)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def _lifespan(_app: FastAPI) -> AsyncIterator[None]:
    """Startup: Faz 10b, madde 2 (see docs/roadmap.md and
    app/services/job_recovery.py) — anything still 'processing' the
    moment this fresh process starts up was orphaned by an earlier
    crash/restart, not started by this process. No-ops without
    `SUPABASE_SERVICE_ROLE_KEY` configured — same "best-effort if
    configured" contract as account deletion (see account_service.py) —
    and never blocks the app from starting even if Supabase itself is
    unreachable right now; the next restart tries again.
    """
    if settings.supabase_service_role_key:
        repo = SupabaseRestRepository(settings.supabase_service_role_key)
        try:
            await recover_orphaned_jobs(repo)
        except Exception:
            logger.exception("orphaned AI job recovery failed at startup")
        finally:
            await repo.aclose()
    yield


app = FastAPI(
    title=settings.app_name,
    version="0.1.0",
    description="Multimodal AI processing service for LifeSearch.",
    lifespan=_lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.allowed_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
# Added last so it's the outermost layer — one structured log line per
# request, timing everything below it including CORS handling.
app.middleware("http")(request_logging_middleware)


@app.get("/health", tags=["health"])
async def health_check() -> dict:
    return {"status": "ok", "environment": settings.environment}


app.include_router(ai_router)
app.include_router(search_router)
app.include_router(collections_router)
app.include_router(account_router)

# Remaining routers are added here as each phase lands, e.g.:
# from app.api.items.routes import router as items_router
# app.include_router(items_router)
