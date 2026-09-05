"""Provider-agnostic AI interface (requirements doc, section 5).

Every AI-touching part of the pipeline codes against `AIProvider`, never
against a specific vendor SDK. Swapping OpenAI for Gemini or a local model
later means adding one more subclass here — nothing else changes.
"""

import base64
import io
import json
from abc import ABC, abstractmethod
from typing import Any

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

    async def analyze_image(self, image_bytes: bytes, mime_type: str) -> dict[str, Any]:
        """Returns `{"title", "description", "ocr_text", "tags"}` — see
        requirements doc, section 14. `ocr_text` is every piece of visible
        text transcribed as-is; `description` is what the image actually
        shows. Both feed the same chunk/embed pipeline as notes and PDFs.
        """
        raise NotImplementedError("Image analysis lands in Phase 6 (Image Intelligence).")

    async def transcribe_audio(self, audio_bytes: bytes, mime_type: str) -> str:
        """Returns the spoken-word transcript (requirements doc, section 18)."""
        raise NotImplementedError


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

    async def analyze_image(self, image_bytes: bytes, mime_type: str) -> dict[str, Any]:
        data_url = f"data:{mime_type};base64,{base64.b64encode(image_bytes).decode()}"
        response = await self._client.chat.completions.create(
            model=self._text_model,  # gpt-4o-mini reads images too, no separate vision model
            response_format={"type": "json_object"},
            messages=[
                {
                    "role": "system",
                    "content": (
                        "You analyze a photo or screenshot for a personal search app. "
                        "Respond with strict JSON: "
                        '{"title": string, "description": string, "ocr_text": string, '
                        '"tags": [string, ...]}. title is under 8 words. description is '
                        "1-2 sentences describing what's shown. ocr_text is every piece "
                        'of visible text transcribed as-is, or "" if there is none. tags '
                        "are 3-6 short lowercase keywords."
                    ),
                },
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": "Analyze this image."},
                        {"type": "image_url", "image_url": {"url": data_url}},
                    ],
                },
            ],
        )
        try:
            data = json.loads(response.choices[0].message.content or "{}")
        except json.JSONDecodeError:
            data = {}
        return {
            "title": data.get("title") or "",
            "description": data.get("description") or "",
            "ocr_text": data.get("ocr_text") or "",
            "tags": data.get("tags") or [],
        }

    async def transcribe_audio(self, audio_bytes: bytes, mime_type: str) -> str:
        extension = mime_type.split("/")[-1] or "m4a"
        audio_file = io.BytesIO(audio_bytes)
        audio_file.name = f"voice-note.{extension}"  # whisper needs a filename to infer format
        response = await self._client.audio.transcriptions.create(
            model="whisper-1",
            file=audio_file,
        )
        return response.text


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
