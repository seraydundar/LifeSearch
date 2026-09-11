"""Central application configuration.

All secrets and environment-specific values must come from environment
variables (see `.env.example`). Nothing here should contain a real secret.
"""

from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # App
    app_name: str = "LifeSearch AI Service"
    environment: str = Field(default="local")  # local | staging | production
    debug: bool = Field(default=True)

    # Supabase / Postgres
    supabase_url: str = Field(default="")
    # The publishable/anon key — used as the `apikey` header on every
    # Supabase request the backend makes, including verifying a user's
    # access token via GET /auth/v1/user (see core/security.py). Safe to
    # share; it's the same key the Flutter app ships with.
    supabase_anon_key: str = Field(default="")
    # Only needed for admin-level operations that must bypass RLS: account
    # deletion (account_repository.py) and the startup sweep that recovers
    # AI jobs orphaned by a crash/restart (job_recovery.py) — everything
    # else is scoped by the calling user's own JWT instead. Keep unset
    # until something actually needs it.
    supabase_service_role_key: str = Field(default="")
    database_url: str = Field(default="")

    # AI providers (kept provider-agnostic; only one needs to be set at a time)
    ai_provider: str = Field(default="openai")  # openai | gemini | local
    openai_api_key: str = Field(default="")
    gemini_api_key: str = Field(default="")

    # Local AI provider (Faz 11, madde 6a — see docs/roadmap.md). Text,
    # embeddings and vision go through a separately-installed Ollama
    # server (https://ollama.com) over plain HTTP; nothing here talks to
    # a vendor cloud API. Model names default to small, commonly-pulled
    # ones but assume nothing — `ollama pull <model>` must be run once on
    # whatever machine runs the backend before AI_PROVIDER=local works.
    local_ollama_base_url: str = Field(default="http://localhost:11434")
    local_text_model: str = Field(default="llama3.2")
    local_embedding_model: str = Field(default="nomic-embed-text")
    local_vision_model: str = Field(default="llava")
    # In-process ASR (faster-whisper) — Ollama has no transcription
    # endpoint. "base" balances accuracy/speed/download size for a
    # personal-use backend; bump to "small"/"medium" if a beefier host
    # runs this. Downloaded automatically on first use, cached locally.
    local_whisper_model: str = Field(default="base")

    # CORS
    allowed_origins: list[str] = Field(default_factory=lambda: ["*"])

    # Per-user rate limits (requests/minute) on the endpoints that call an
    # AI provider — each of those calls costs real money and, unlike a
    # plain CRUD request, is slow enough that a client bug (a retry loop,
    # a stuck background sync) or a leaked token could run up a real bill
    # before anyone notices. See core/rate_limit.py.
    rate_limit_ai_per_minute: int = Field(default=10)
    rate_limit_search_per_minute: int = Field(default=30)


@lru_cache
def get_settings() -> Settings:
    return Settings()
