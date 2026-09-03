"""Provider-agnostic AI interface (requirements doc, section 5).

Every AI-touching part of the pipeline codes against `AIProvider`, never
against a specific vendor SDK. Swapping OpenAI for Gemini or a local model
later means adding one more subclass here — nothing else changes.
"""

from abc import ABC, abstractmethod

from openai import AsyncOpenAI

from ..core.config import Settings


class AIProvider(ABC):
    @abstractmethod
    async def generate_text(self, prompt: str, *, system: str | None = None) -> str:
        """Used by RAG answers (Phase 7) and AI-generated summaries/tags."""

    @abstractmethod
    async def generate_embedding(self, text: str) -> list[float]:
        """Embed a single string — mainly for query embeddings at search time."""

    @abstractmethod
    async def generate_embeddings(self, texts: list[str]) -> list[list[float]]:
        """Batch embed — what the chunking pipeline actually uses."""

    async def analyze_image(self, image_bytes: bytes, mime_type: str) -> dict:
        raise NotImplementedError("Image analysis lands in Phase 6 (Image Intelligence).")

    async def transcribe_audio(self, audio_bytes: bytes, mime_type: str) -> str:
        raise NotImplementedError("Audio transcription lands in Phase 8 (Audio + URL).")


class OpenAIProvider(AIProvider):
    """Reference implementation. Embedding dimensions must match the
    `chunks.embedding` column in infra/supabase/migrations/0001_init.sql
    (vector(1536) — text-embedding-3-small's native size)."""

    def __init__(
        self,
        api_key: str,
        *,
        embedding_model: str = "text-embedding-3-small",
        text_model: str = "gpt-4o-mini",
    ) -> None:
        self._client = AsyncOpenAI(api_key=api_key)
        self._embedding_model = embedding_model
        self._text_model = text_model

    async def generate_text(self, prompt: str, *, system: str | None = None) -> str:
        messages = []
        if system:
            messages.append({"role": "system", "content": system})
        messages.append({"role": "user", "content": prompt})
        response = await self._client.chat.completions.create(
            model=self._text_model,
            messages=messages,
        )
        return response.choices[0].message.content or ""

    async def generate_embedding(self, text: str) -> list[float]:
        embeddings = await self.generate_embeddings([text])
        return embeddings[0]

    async def generate_embeddings(self, texts: list[str]) -> list[list[float]]:
        if not texts:
            return []
        response = await self._client.embeddings.create(
            model=self._embedding_model,
            input=texts,
        )
        # OpenAI preserves input order in `data`, but sort by index defensively.
        ordered = sorted(response.data, key=lambda d: d.index)
        return [item.embedding for item in ordered]


def get_ai_provider(settings: Settings) -> AIProvider:
    match settings.ai_provider:
        case "openai":
            if not settings.openai_api_key:
                raise RuntimeError(
                    "AI_PROVIDER=openai but OPENAI_API_KEY is not set (backend/.env)."
                )
            return OpenAIProvider(settings.openai_api_key)
        case "gemini":
            raise NotImplementedError("GeminiProvider isn't implemented yet.")
        case "local":
            raise NotImplementedError("LocalModelProvider isn't implemented yet.")
        case other:
            raise ValueError(f"Unknown AI_PROVIDER '{other}'.")
