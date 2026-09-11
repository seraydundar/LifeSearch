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

from google import genai
from google.genai import types
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


class GeminiProvider(AIProvider):
    """Google's Gemini models via `google-genai` — the current unified
    SDK (the older `google-generativeai` package is in maintenance mode).

    **Embedding dimension mismatch, and why the fix here is safe**:
    `text-embedding-004` outputs 768-dim vectors, but `chunks.embedding`
    is a fixed `vector(1536)` column (sized for OpenAI's
    `text-embedding-3-small` — see infra/supabase/migrations/0001_init.sql).
    `generate_embeddings()` zero-pads every vector out to 1536 dims to
    fit that column without a schema change. That's mathematically
    inert for cosine similarity specifically: appending the same-length
    all-zero tail to two vectors changes neither their dot product nor
    either one's norm, so `cosine(pad(a), pad(b)) == cosine(a, b)`
    exactly — comparing two Gemini-embedded (and therefore identically
    padded) chunks is unaffected.

    **What padding does NOT fix**: it doesn't make a Gemini embedding
    comparable to an OpenAI one — the two models' embedding spaces
    aren't related at all, padded or not. Switching `AI_PROVIDER` on a
    database that already has embeddings from the *other* provider
    needs a full re-embed of every existing chunk; this backend has no
    migration for that, so don't switch providers on a live archive
    without doing one by hand first.
    """

    _EMBEDDING_DIMENSIONS = 1536  # chunks.embedding's fixed column size
    _NATIVE_EMBEDDING_DIMENSIONS = 768  # text-embedding-004's own output size

    def __init__(
        self,
        api_key: str,
        *,
        embedding_model: str = "text-embedding-004",
        text_model: str = "gemini-2.0-flash",
    ) -> None:
        self._client = genai.Client(api_key=api_key)
        self._embedding_model = embedding_model
        self._text_model = text_model

    async def generate_text(self, prompt: str, *, system: str | None = None) -> str:
        config = types.GenerateContentConfig(system_instruction=system) if system else None
        response = await self._client.aio.models.generate_content(
            model=self._text_model,
            contents=prompt,
            config=config,
        )
        return response.text or ""

    async def generate_embedding(self, text: str) -> list[float]:
        embeddings = await self.generate_embeddings([text])
        return embeddings[0]

    async def generate_embeddings(self, texts: list[str]) -> list[list[float]]:
        if not texts:
            return []
        response = await self._client.aio.models.embed_content(
            model=self._embedding_model,
            contents=texts,
        )
        return [_pad_embedding(e.values, self._EMBEDDING_DIMENSIONS) for e in response.embeddings]

    async def analyze_image(self, image_bytes: bytes, mime_type: str) -> dict[str, Any]:
        response = await self._client.aio.models.generate_content(
            model=self._text_model,
            contents=[
                types.Part.from_bytes(data=image_bytes, mime_type=mime_type),
                "You analyze a photo or screenshot for a personal search app. "
                "Respond with strict JSON: "
                '{"title": string, "description": string, "ocr_text": string, '
                '"tags": [string, ...]}. title is under 8 words. description is '
                "1-2 sentences describing what's shown. ocr_text is every piece "
                'of visible text transcribed as-is, or "" if there is none. tags '
                "are 3-6 short lowercase keywords.",
            ],
            config=types.GenerateContentConfig(response_mime_type="application/json"),
        )
        try:
            data = json.loads(response.text or "{}")
        except json.JSONDecodeError:
            data = {}
        return {
            "title": data.get("title") or "",
            "description": data.get("description") or "",
            "ocr_text": data.get("ocr_text") or "",
            "tags": data.get("tags") or [],
        }

    async def transcribe_audio(self, audio_bytes: bytes, mime_type: str) -> str:
        # Gemini has no dedicated ASR endpoint like Whisper — its
        # multimodal models take audio directly as an input part instead.
        response = await self._client.aio.models.generate_content(
            model=self._text_model,
            contents=[
                types.Part.from_bytes(data=audio_bytes, mime_type=mime_type),
                "Transcribe this audio exactly as spoken, word for word. "
                "Respond with only the transcript, no commentary.",
            ],
        )
        return response.text or ""


def _pad_embedding(values: list[float], target_dimensions: int) -> list[float]:
    """Zero-pads (or, defensively, truncates) `values` out to exactly
    `target_dimensions` — see `GeminiProvider`'s own docstring for why
    padding with zeros is a mathematically safe way to fit a smaller
    embedding into a larger fixed-size vector column.
    """
    if len(values) >= target_dimensions:
        return values[:target_dimensions]
    return values + [0.0] * (target_dimensions - len(values))


def get_ai_provider(settings: Settings) -> AIProvider:
    match settings.ai_provider:
        case "openai":
            if not settings.openai_api_key:
                raise RuntimeError(
                    "AI_PROVIDER=openai but OPENAI_API_KEY is not set (backend/.env)."
                )
            return OpenAIProvider(settings.openai_api_key)
        case "gemini":
            if not settings.gemini_api_key:
                raise RuntimeError(
                    "AI_PROVIDER=gemini but GEMINI_API_KEY is not set (backend/.env)."
                )
            return GeminiProvider(settings.gemini_api_key)
        case "local":
            raise NotImplementedError(
                "LocalModelProvider isn't implemented yet — bundled with Faz 11's "
                "offline-semantic-search work (see docs/roadmap.md), since both need "
                "the same local inference engine."
            )
        case other:
            raise ValueError(f"Unknown AI_PROVIDER '{other}'.")
