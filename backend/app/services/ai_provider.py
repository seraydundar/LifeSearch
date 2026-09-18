"""Provider-agnostic AI interface (requirements doc, section 5).

Every AI-touching part of the pipeline codes against `AIProvider`, never
against a specific vendor SDK. Swapping OpenAI for Gemini or a local model
later means adding one more subclass here — nothing else changes.
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

# Shared JSON-contract instructions for `analyze_image` — identical across
# all three providers below, so it's factored out once instead of being
# hand-copied a third and fourth time now that a screenshot gets its own
# variant of the rest of the prompt.
_IMAGE_ANALYSIS_JSON_CONTRACT = (
    'Respond with strict JSON: {"title": string, "description": string, '
    '"ocr_text": string, "tags": [string, ...]}. title is under 8 words. '
    "tags are 3-6 short lowercase keywords."
)


def _vision_system_prompt(*, is_screenshot: bool) -> str:
    """P2-06 (docs/requirements-audit-2026-09-13.md): a screenshot isn't a
    photo of the physical world — it's a picture of a screen (an app,
    website, chat, error message, document), and what makes it useful to
    find later is usually the text on it, not a scene description. The
    generic "photo" prompt used to be reused verbatim for screenshots too
    (Faz 15 added the *item type*, `ItemType.screenshot`, but never a
    distinct prompt to go with it), so `ocr_text` on a screenshot was only
    ever as complete as a "describe this photo" prompt happened to make it.
    """
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
    #: Matches `Settings.ai_provider`'s own values ("openai" | "gemini" |
    #: "local") — set by each subclass. Tagged onto every chunk this
    #: provider embeds (P3, docs/requirements-audit-2026-09-13.md), so a
    #: later switch can tell which chunks it actually produced.
    provider_name: str

    @property
    @abstractmethod
    def embedding_model(self) -> str:
        """The exact model name `generate_embedding(s)` calls with —
        together with `provider_name`, identifies the embedding space a
        chunk's vector actually lives in (P3). Two different models can
        share `provider_name` (e.g. Gemini's embedding model has been
        swapped once already, see `GeminiProvider`'s docstring) and
        produce vectors that aren't comparable to each other at all.
        """

    @abstractmethod
    async def generate_text(self, prompt: str, *, system: str | None = None) -> str:
        """Used by RAG answers (Phase 7) and AI-generated summaries/tags."""

    @abstractmethod
    async def generate_embedding(self, text: str) -> list[float]:
        """Embed a single string — mainly for query embeddings at search time."""

    @abstractmethod
    async def generate_embeddings(self, texts: list[str]) -> list[list[float]]:
        """Batch embed — what the chunking pipeline actually uses."""

    async def analyze_image(
        self, image_bytes: bytes, mime_type: str, *, is_screenshot: bool = False
    ) -> dict[str, Any]:
        """Returns `{"title", "description", "ocr_text", "tags"}` — see
        requirements doc, section 14. `ocr_text` is every piece of visible
        text transcribed as-is; `description` is what the image actually
        shows. Both feed the same chunk/embed pipeline as notes and PDFs.

        `is_screenshot` (P2-06, docs/requirements-audit-2026-09-13.md)
        switches to a prompt tuned for a picture of a screen rather than a
        photo — see `_vision_system_prompt`. Defaults to `False` so a
        caller with no opinion (e.g. OCR-ing a scanned PDF page) keeps the
        original photo-description behavior.
        """
        raise NotImplementedError("Image analysis lands in Phase 6 (Image Intelligence).")

    async def transcribe_audio(self, audio_bytes: bytes, mime_type: str) -> str:
        """Returns the spoken-word transcript (requirements doc, section 18)."""
        raise NotImplementedError


class OpenAIProvider(AIProvider):
    """Reference implementation. Embedding dimensions must match the
    `chunks.embedding` column in infra/supabase/migrations/0001_init.sql
    (vector(1536) — text-embedding-3-small's native size)."""

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
        # OpenAI preserves input order in `data`, but sort by index defensively.
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
    """Google's Gemini models via `google-genai` — the current unified
    SDK (the older `google-generativeai` package is in maintenance mode).

    **Defaults, and why they keep needing to be revisited** (Faz 12,
    madde 10, denetim düzeltmesi — see docs/roadmap.md): this provider's
    original defaults (`text-embedding-004`, `gemini-2.0-flash`) were
    both real, working models when Faz 11 madde 4 shipped them — and
    were both later shut down by Google (confirmed against Google's own
    changelog: `text-embedding-004` on 2026-01-14, `gemini-2.0-flash` on
    2026-06-01), silently turning "just add an API key" into "silently
    broken" for anyone who never overrode `LOCAL_TEXT_MODEL`/
    `LOCAL_EMBEDDING_MODEL`-style env vars. There's no way to pin this
    forever — Google's own model lifecycle means today's stable default
    will eventually be deprecated too. `gemini-3.8-flash`/
    `gemini-embedding-2` are the current (2026-09) stable, non-preview
    replacements, verified against Google's changelog at fix time; if a
    provider call ever starts failing with a "model not found" style
    error, that changelog is the first place to check.

    **`gemini-embedding-2` requests its output at exactly `chunks.
    embedding`'s column size** (`vector(1536)`, sized for OpenAI's
    `text-embedding-3-small` — see
    infra/supabase/migrations/0001_init.sql) via `output_dimensionality`
    — the model is trained with Matryoshka Representation Learning
    specifically to support this (768/1536/3072 are Google's own
    documented recommended sizes) and auto-normalizes the truncated
    output itself, unlike the older `text-embedding-004`, which only
    ever output a fixed 768 dims that then had to be zero-padded out to
    1536 here. `_pad_embedding()` is kept as a defensive no-op (it's a
    no-op whenever the input is already the target length) rather than
    trusted to newly do the heavy lifting — if some future embedding
    model doesn't support `output_dimensionality`, this still degrades
    to the same zero-padding as before, not a hard failure.

    **What none of this fixes**: it doesn't make a Gemini embedding
    comparable to an OpenAI (or a *previous Gemini model's*) one — each
    model's embedding space is its own, unrelated to any other's, right
    dimension or not. Switching `AI_PROVIDER`, or bumping
    `embedding_model` to a different model than whatever embedded the
    existing archive, needs a full re-embed of every existing chunk —
    `reembedding_service.py` (P3, docs/requirements-audit-2026-09-13.md)
    is the on-request button that does this: `chunks.embedding_provider`/
    `embedding_model` tag which space each chunk's vector actually lives
    in, and search (`match_chunks_hybrid`) quietly excludes any chunk
    tagged with a different one than what's currently configured, so a
    switch never surfaces silently-wrong similarity scores while the
    re-embed is pending.
    """

    provider_name = "gemini"
    _EMBEDDING_DIMENSIONS = 1536  # chunks.embedding's fixed column size

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


class LocalProvider(AIProvider):
    """A fully local, no-cloud-API provider (Faz 11, madde 6a — see
    docs/roadmap.md). Text, embeddings and vision go through **Ollama**
    (https://ollama.com), a server installed and run separately from
    this backend, reached over plain HTTP — nothing here talks to a
    vendor cloud API, and no request ever leaves the machine Ollama runs
    on. Transcription is the one exception: Ollama has no ASR endpoint,
    so `transcribe_audio` runs **faster-whisper** in-process instead.

    None of this can be verified end-to-end from inside this repo — it
    needs Ollama actually installed, running, and the right models
    pulled (`ollama pull llama3.2`, etc.) on whatever machine runs the
    backend. See docs/local-ai-provider-setup.md for that checklist;
    `_post()` below at least turns "Ollama isn't running" into a clear
    error instead of a raw connection-refused traceback.

    **Embedding dimension**: whatever the configured embedding model
    natively outputs (768 for `nomic-embed-text`, 1024 for
    `mxbai-embed-large`, etc.) gets zero-padded out to the fixed
    `vector(1536)` column, exactly like `GeminiProvider` — see that
    class's docstring for why this is mathematically safe. Same caveat
    applies: switching `AI_PROVIDER` on a database with embeddings from
    a *different* provider needs a full manual re-embed first — see
    `reembedding_service.py` for the (P3) button that now does exactly
    that, on request.
    """

    provider_name = "local"
    _EMBEDDING_DIMENSIONS = 1536  # chunks.embedding's fixed column size

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
        self._whisper_model: Any = None  # lazily loaded — see _get_whisper_model()

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
        # Ollama's chat API takes images as a list of base64 strings on
        # the message itself (no separate content-parts structure like
        # OpenAI/Gemini) — mime_type isn't needed, the model infers format.
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
        # faster-whisper is CPU/GPU-bound and synchronous — run it off
        # the event loop so one transcription doesn't stall every other
        # request this backend is handling.
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
            return LocalProvider(
                base_url=settings.local_ollama_base_url,
                text_model=settings.local_text_model,
                embedding_model=settings.local_embedding_model,
                vision_model=settings.local_vision_model,
                whisper_model_size=settings.local_whisper_model,
            )
        case other:
            raise ValueError(f"Unknown AI_PROVIDER '{other}'.")
