"""Provider-agnostic AI interface; every caller codes against `AIProvider`,
never a vendor SDK, so adding a provider is one new subclass.
"""

import asyncio
import base64
import io
import json
import tempfile
from abc import ABC, abstractmethod
from typing import Any

import httpx
from google import genai
from google.genai import types
from openai import AsyncOpenAI

from ..core.config import Settings

# Shared JSON-contract instructions for analyze_image, same across all providers.
_IMAGE_ANALYSIS_JSON_CONTRACT = (
    'Respond with strict JSON: {"title": string, "description": string, '
    '"ocr_text": string, "tags": [string, ...]}. title is under 8 words. '
    "tags are 3-6 short lowercase keywords."
)


def _vision_system_prompt(*, is_screenshot: bool) -> str:
    """A screenshot needs its on-screen text transcribed, not a scene description."""
    if is_screenshot:
        return (
            "You analyze a screenshot for a personal search app — a "
            "picture of a screen (an app, website, chat, error message, "
            "document, etc.), not a photo of the physical world. "
            f"{_IMAGE_ANALYSIS_JSON_CONTRACT} description names the app/"
            "site/screen and what it's showing, in 1-2 sentences. ocr_text "
            "is the most important field here: transcribe EVERY piece of "
            "visible text, in reading order, as completely and accurately "
            'as possible, or "" only if there truly is none — a screenshot '
            "is usually looked up again for its text. Include the app or "
            "site name among the tags if it's identifiable."
        )
    return (
        "You analyze a photo for a personal search app. "
        f"{_IMAGE_ANALYSIS_JSON_CONTRACT} description is 1-2 sentences "
        "describing what's shown. ocr_text is every piece of visible text "
        'transcribed as-is, or "" if there is none.'
    )


class AIProvider(ABC):
    # Tagged onto every chunk this provider embeds, so a later switch can
    # tell which chunks it actually produced.
    provider_name: str

    @property
    @abstractmethod
    def embedding_model(self) -> str:
        """Together with `provider_name`, identifies the embedding space a
        chunk's vector lives in — two models can share `provider_name` yet
        produce incomparable vectors.
        """

    @abstractmethod
    async def generate_text(self, prompt: str, *, system: str | None = None) -> str: ...

    @abstractmethod
    async def generate_embedding(self, text: str) -> list[float]: ...

    @abstractmethod
    async def generate_embeddings(self, texts: list[str]) -> list[list[float]]: ...

    async def analyze_image(
        self, image_bytes: bytes, mime_type: str, *, is_screenshot: bool = False
    ) -> dict[str, Any]:
        """Returns `{"title", "description", "ocr_text", "tags"}`."""
        raise NotImplementedError("Image analysis lands in Phase 6 (Image Intelligence).")

    async def transcribe_audio(self, audio_bytes: bytes, mime_type: str) -> str:
        raise NotImplementedError


class OpenAIProvider(AIProvider):
    """Reference implementation. Embedding dims must match chunks.embedding's
    column size (vector(1536), text-embedding-3-small's native size).
    """

    provider_name = "openai"

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

    @property
    def embedding_model(self) -> str:
        return self._embedding_model

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
        # Sort by index defensively even though OpenAI preserves input order.
        ordered = sorted(response.data, key=lambda d: d.index)
        return [item.embedding for item in ordered]

    async def analyze_image(
        self, image_bytes: bytes, mime_type: str, *, is_screenshot: bool = False
    ) -> dict[str, Any]:
        data_url = f"data:{mime_type};base64,{base64.b64encode(image_bytes).decode()}"
        response = await self._client.chat.completions.create(
            model=self._text_model,  # gpt-4o-mini reads images too, no separate vision model
            response_format={"type": "json_object"},
            messages=[
                {
                    "role": "system",
                    "content": _vision_system_prompt(is_screenshot=is_screenshot),
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
    """Google's Gemini models via `google-genai`. Default models get
    deprecated by Google over time (past defaults were shut down after
    shipping) — a "model not found" error means check Google's changelog
    for current replacements. `gemini-embedding-2` targets chunks.embedding's
    column size directly via `output_dimensionality`; `_pad_embedding()`
    stays as a defensive fallback for models that don't support it. None of
    this makes embeddings from different models/providers comparable —
    switching needs a full re-embed via reembedding_service.py.
    """

    provider_name = "gemini"
    _EMBEDDING_DIMENSIONS = 1536  # chunks.embedding's column size

    def __init__(
        self,
        api_key: str,
        *,
        embedding_model: str = "gemini-embedding-2",
        text_model: str = "gemini-3.8-flash",
    ) -> None:
        self._client = genai.Client(api_key=api_key)
        self._embedding_model = embedding_model
        self._text_model = text_model

    @property
    def embedding_model(self) -> str:
        return self._embedding_model

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
            config=types.EmbedContentConfig(output_dimensionality=self._EMBEDDING_DIMENSIONS),
        )
        return [_pad_embedding(e.values, self._EMBEDDING_DIMENSIONS) for e in response.embeddings]

    async def analyze_image(
        self, image_bytes: bytes, mime_type: str, *, is_screenshot: bool = False
    ) -> dict[str, Any]:
        response = await self._client.aio.models.generate_content(
            model=self._text_model,
            contents=[
                types.Part.from_bytes(data=image_bytes, mime_type=mime_type),
                _vision_system_prompt(is_screenshot=is_screenshot),
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
        # No dedicated ASR endpoint; the multimodal model takes audio as an input part.
        response = await self._client.aio.models.generate_content(
            model=self._text_model,
            contents=[
                types.Part.from_bytes(data=audio_bytes, mime_type=mime_type),
                "Transcribe this audio exactly as spoken, word for word. "
                "Respond with only the transcript, no commentary.",
            ],
        )
        return response.text or ""


class LocalProvider(AIProvider):
    """Fully local, no-cloud-API: text/embeddings/vision go through Ollama
    (a separately-run server, see docs/local-ai-provider-setup.md); audio
    transcription runs faster-whisper in-process since Ollama has no ASR.
    Embeddings are zero-padded to the fixed vector(1536) column, like
    GeminiProvider; switching providers needs a re-embed (reembedding_service.py).
    """

    provider_name = "local"
    _EMBEDDING_DIMENSIONS = 1536  # chunks.embedding's column size

    def __init__(
        self,
        *,
        base_url: str,
        text_model: str,
        embedding_model: str,
        vision_model: str,
        whisper_model_size: str,
    ) -> None:
        self._client = httpx.AsyncClient(base_url=base_url, timeout=120.0)
        self._text_model = text_model
        self._embedding_model = embedding_model
        self._vision_model = vision_model
        self._whisper_model_size = whisper_model_size
        self._whisper_model: Any = None  # lazy-loaded

    @property
    def embedding_model(self) -> str:
        return self._embedding_model

    async def generate_text(self, prompt: str, *, system: str | None = None) -> str:
        messages = []
        if system:
            messages.append({"role": "system", "content": system})
        messages.append({"role": "user", "content": prompt})
        return await self._chat(self._text_model, messages)

    async def generate_embedding(self, text: str) -> list[float]:
        embeddings = await self.generate_embeddings([text])
        return embeddings[0]

    async def generate_embeddings(self, texts: list[str]) -> list[list[float]]:
        if not texts:
            return []
        data = await self._post("/api/embed", {"model": self._embedding_model, "input": texts})
        return [_pad_embedding(e, self._EMBEDDING_DIMENSIONS) for e in data["embeddings"]]

    async def analyze_image(
        self, image_bytes: bytes, mime_type: str, *, is_screenshot: bool = False
    ) -> dict[str, Any]:
        # Ollama takes images as base64 strings on the message, no mime_type needed.
        messages = [
            {
                "role": "user",
                "content": _vision_system_prompt(is_screenshot=is_screenshot),
                "images": [base64.b64encode(image_bytes).decode()],
            }
        ]
        content = await self._chat(self._vision_model, messages, response_format="json")
        try:
            data = json.loads(content or "{}")
        except json.JSONDecodeError:
            data = {}
        return {
            "title": data.get("title") or "",
            "description": data.get("description") or "",
            "ocr_text": data.get("ocr_text") or "",
            "tags": data.get("tags") or [],
        }

    async def transcribe_audio(self, audio_bytes: bytes, mime_type: str) -> str:
        # Synchronous/CPU-bound; run off the event loop so it doesn't stall other requests.
        return await asyncio.to_thread(self._transcribe_sync, audio_bytes, mime_type)

    async def _chat(
        self, model: str, messages: list[dict[str, Any]], *, response_format: str | None = None
    ) -> str:
        payload: dict[str, Any] = {"model": model, "messages": messages, "stream": False}
        if response_format:
            payload["format"] = response_format
        data = await self._post("/api/chat", payload)
        return data["message"]["content"] or ""

    async def _post(self, path: str, json_body: dict[str, Any]) -> dict[str, Any]:
        try:
            response = await self._client.post(path, json=json_body)
        except httpx.ConnectError as exc:
            raise RuntimeError(
                f"Couldn't reach Ollama at {self._client.base_url}{path} ({exc}). "
                "AI_PROVIDER=local needs Ollama installed and running separately — "
                "see docs/local-ai-provider-setup.md."
            ) from exc
        response.raise_for_status()
        return response.json()

    def _get_whisper_model(self) -> Any:
        if self._whisper_model is None:
            from faster_whisper import WhisperModel

            self._whisper_model = WhisperModel(
                self._whisper_model_size, device="cpu", compute_type="int8"
            )
        return self._whisper_model

    def _transcribe_sync(self, audio_bytes: bytes, mime_type: str) -> str:
        extension = mime_type.split("/")[-1] or "m4a"
        with tempfile.NamedTemporaryFile(suffix=f".{extension}") as audio_file:
            audio_file.write(audio_bytes)
            audio_file.flush()
            segments, _info = self._get_whisper_model().transcribe(audio_file.name)
            return " ".join(segment.text.strip() for segment in segments).strip()


def _pad_embedding(values: list[float], target_dimensions: int) -> list[float]:
    """Zero-pads (or defensively truncates) to exactly `target_dimensions`."""
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
            return LocalProvider(
                base_url=settings.local_ollama_base_url,
                text_model=settings.local_text_model,
                embedding_model=settings.local_embedding_model,
                vision_model=settings.local_vision_model,
                whisper_model_size=settings.local_whisper_model,
            )
        case other:
            raise ValueError(f"Unknown AI_PROVIDER '{other}'.")
