"""Central app config; all secrets come from env vars (see .env.example)."""

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
    # Publishable/anon key; safe to share, same one the Flutter app ships with.
    supabase_anon_key: str = Field(default="")
    # Bypasses RLS; only needed for account deletion and job_recovery's sweep. Keep unset otherwise.
    supabase_service_role_key: str = Field(default="")
    database_url: str = Field(default="")

    # AI providers (kept provider-agnostic; only one needs to be set at a time)
    ai_provider: str = Field(default="openai")  # openai | gemini | local
    openai_api_key: str = Field(default="")
    gemini_api_key: str = Field(default="")

    # Via a separate Ollama server; `ollama pull <model>` must run once first.
    local_ollama_base_url: str = Field(default="http://localhost:11434")
    local_text_model: str = Field(default="llama3.2")
    local_embedding_model: str = Field(default="nomic-embed-text")
    local_vision_model: str = Field(default="llava")
    # In-process ASR (faster-whisper); Ollama has no transcription endpoint.
    local_whisper_model: str = Field(default="base")

    # CORS
    allowed_origins: list[str] = Field(default_factory=lambda: ["*"])

    # Per-user limits on endpoints calling an AI provider (real cost/call). See core/rate_limit.py.
    rate_limit_ai_per_minute: int = Field(default=10)
    rate_limit_search_per_minute: int = Field(default=30)


@lru_cache
def get_settings() -> Settings:
    return Settings()
