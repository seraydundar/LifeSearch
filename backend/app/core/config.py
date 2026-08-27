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
    supabase_service_role_key: str = Field(default="")
    database_url: str = Field(default="")

    # AI providers (kept provider-agnostic; only one needs to be set at a time)
    ai_provider: str = Field(default="openai")  # openai | gemini | local
    openai_api_key: str = Field(default="")
    gemini_api_key: str = Field(default="")

    # Auth
    jwt_secret: str = Field(default="")

    # CORS
    allowed_origins: list[str] = Field(default_factory=lambda: ["*"])


@lru_cache
def get_settings() -> Settings:
    return Settings()
