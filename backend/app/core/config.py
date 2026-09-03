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
    # Only needed for admin-level operations that must bypass RLS — none
    # of the Phase 4 pipeline does; every request is scoped by the calling
    # user's own JWT instead. Keep unset until something actually needs it.
    supabase_service_role_key: str = Field(default="")
    database_url: str = Field(default="")

    # AI providers (kept provider-agnostic; only one needs to be set at a time)
    ai_provider: str = Field(default="openai")  # openai | gemini | local
    openai_api_key: str = Field(default="")
    gemini_api_key: str = Field(default="")

    # CORS
    allowed_origins: list[str] = Field(default_factory=lambda: ["*"])


@lru_cache
def get_settings() -> Settings:
    return Settings()
