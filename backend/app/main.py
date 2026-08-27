"""LifeSearch AI Service — FastAPI entrypoint.

This service owns every AI-heavy operation (OCR, chunking, embeddings,
vector/hybrid search, RAG, vision, transcription). The Flutter app talks
to Supabase directly for plain CRUD + auth, and to this service for
anything that needs an AI provider — so provider API keys never live in
the mobile app.

Only a health check is wired up for now. Feature routers under
`app/api/*` are scaffolded but intentionally not included yet — they get
wired in starting Phase 4 of the roadmap (see docs/requirements.md).
"""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.core.config import get_settings
from app.core.logging import configure_logging

settings = get_settings()
configure_logging(debug=settings.debug)

app = FastAPI(
    title=settings.app_name,
    version="0.1.0",
    description="Multimodal AI processing service for LifeSearch.",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.allowed_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health", tags=["health"])
async def health_check() -> dict:
    return {"status": "ok", "environment": settings.environment}


# Feature routers are added here as each phase lands, e.g.:
# from app.api.items.routes import router as items_router
# app.include_router(items_router)
