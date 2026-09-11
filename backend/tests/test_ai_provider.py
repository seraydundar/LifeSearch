import base64
import json

import httpx
import pytest

from app.core.config import Settings
from app.services.ai_provider import (
    GeminiProvider,
    LocalProvider,
    OpenAIProvider,
    _pad_embedding,
    get_ai_provider,
)


def test_openai_provider_selected_when_configured():
    settings = Settings(ai_provider="openai", openai_api_key="sk-test")
    provider = get_ai_provider(settings)
    assert isinstance(provider, OpenAIProvider)


def test_openai_without_a_key_raises_a_clear_error():
    settings = Settings(ai_provider="openai", openai_api_key="")
    with pytest.raises(RuntimeError, match="OPENAI_API_KEY"):
        get_ai_provider(settings)


def test_gemini_provider_selected_when_configured():
    settings = Settings(ai_provider="gemini", gemini_api_key="test-key")
    provider = get_ai_provider(settings)
    assert isinstance(provider, GeminiProvider)


def test_gemini_without_a_key_raises_a_clear_error():
    settings = Settings(ai_provider="gemini", gemini_api_key="")
    with pytest.raises(RuntimeError, match="GEMINI_API_KEY"):
        get_ai_provider(settings)


def test_local_provider_selected_when_configured():
    # No API key needed — Ollama doesn't use one — but the settings
    # still carry the model names LocalProvider is built from.
    settings = Settings(ai_provider="local")
    provider = get_ai_provider(settings)
    assert isinstance(provider, LocalProvider)


def test_unknown_provider_name_is_rejected():
    with pytest.raises(ValueError, match="Unknown AI_PROVIDER"):
        get_ai_provider(Settings(ai_provider="not-a-real-provider"))


class TestPadEmbedding:
    """`GeminiProvider.generate_embeddings()`'s zero-padding — Gemini's
    `text-embedding-004` outputs 768 dims, `chunks.embedding` is a fixed
    `vector(1536)` column (see infra/supabase/migrations/0001_init.sql).
    Getting this wrong would silently corrupt every Gemini-embedded
    chunk's vector search, so it gets its own direct tests rather than
    relying only on an end-to-end call through the real API.
    """

    def test_pads_a_shorter_embedding_with_trailing_zeros(self):
        result = _pad_embedding([1.0, 2.0, 3.0], 6)
        assert result == [1.0, 2.0, 3.0, 0.0, 0.0, 0.0]

    def test_leaves_an_already_correct_length_embedding_untouched(self):
        result = _pad_embedding([1.0, 2.0, 3.0], 3)
        assert result == [1.0, 2.0, 3.0]

    def test_truncates_defensively_if_somehow_too_long(self):
        result = _pad_embedding([1.0, 2.0, 3.0, 4.0], 3)
        assert result == [1.0, 2.0, 3.0]

    def test_padding_never_changes_cosine_similarity_between_two_vectors(self):
        """The actual property that makes zero-padding safe (see
        `GeminiProvider`'s docstring) — not just "the shape is right",
        but that similarity search among Gemini-embedded chunks is
        mathematically unaffected by the padding at all.
        """
        import math

        def cosine(a: list[float], b: list[float]) -> float:
            dot = sum(x * y for x, y in zip(a, b, strict=True))
            norm_a = math.sqrt(sum(x * x for x in a))
            norm_b = math.sqrt(sum(y * y for y in b))
            return dot / (norm_a * norm_b)

        a = [0.1, 0.7, -0.3, 0.5]
        b = [0.4, -0.2, 0.6, 0.1]

        before = cosine(a, b)
        after = cosine(_pad_embedding(a, 10), _pad_embedding(b, 10))

        assert after == pytest.approx(before)


def _local_provider_with_transport(handler) -> LocalProvider:
    provider = LocalProvider(
        base_url="http://localhost:11434",
        text_model="llama3.2",
        embedding_model="nomic-embed-text",
        vision_model="llava",
        whisper_model_size="base",
    )
    # Swap in a transport that never touches the network, after
    # construction — same pattern as test_items_repository_idempotency.py
    # and test_url_service_ssrf.py: build the object exactly the way
    # production code does, only redirect where its requests actually go.
    provider._client = httpx.AsyncClient(
        base_url="http://localhost:11434", transport=httpx.MockTransport(handler)
    )
    return provider


class TestLocalProviderOllamaCalls:
    """`LocalProvider` talks to a separately-run Ollama server over
    plain HTTP (see docs/local-ai-provider-setup.md) — these pin down
    the exact request/response shapes against Ollama's documented API
    (`/api/chat`, `/api/embed`) without needing a real Ollama install.
    """

    @pytest.mark.asyncio
    async def test_generate_text_posts_chat_and_reads_message_content(self):
        seen: list[httpx.Request] = []

        def handler(request: httpx.Request) -> httpx.Response:
            seen.append(request)
            return httpx.Response(
                200, json={"message": {"role": "assistant", "content": "hi there"}}
            )

        provider = _local_provider_with_transport(handler)
        result = await provider.generate_text("hello", system="be nice")

        assert result == "hi there"
        assert len(seen) == 1
        body = json.loads(seen[0].content)
        assert body["model"] == "llama3.2"
        assert body["stream"] is False
        assert body["messages"] == [
            {"role": "system", "content": "be nice"},
            {"role": "user", "content": "hello"},
        ]

    @pytest.mark.asyncio
    async def test_generate_embeddings_posts_embed_and_pads_to_1536(self):
        def handler(request: httpx.Request) -> httpx.Response:
            body = json.loads(request.content)
            assert body == {"model": "nomic-embed-text", "input": ["a", "b"]}
            return httpx.Response(200, json={"embeddings": [[1.0, 2.0], [3.0, 4.0]]})

        provider = _local_provider_with_transport(handler)
        result = await provider.generate_embeddings(["a", "b"])

        assert len(result) == 2
        assert all(len(vec) == 1536 for vec in result)
        assert result[0][:2] == [1.0, 2.0]
        assert result[0][2:] == [0.0] * 1534

    @pytest.mark.asyncio
    async def test_generate_embeddings_returns_empty_list_without_a_request(self):
        def handler(request: httpx.Request) -> httpx.Response:
            raise AssertionError("should not have made a request for an empty list")

        provider = _local_provider_with_transport(handler)
        assert await provider.generate_embeddings([]) == []

    @pytest.mark.asyncio
    async def test_analyze_image_sends_base64_images_and_parses_json_response(self):
        def handler(request: httpx.Request) -> httpx.Response:
            body = json.loads(request.content)
            assert body["model"] == "llava"
            assert body["format"] == "json"
            assert body["messages"][0]["images"] == [base64.b64encode(b"fake-bytes").decode()]
            return httpx.Response(
                200,
                json={
                    "message": {
                        "role": "assistant",
                        "content": json.dumps(
                            {
                                "title": "A cat",
                                "description": "A cat on a couch.",
                                "ocr_text": "",
                                "tags": ["cat", "couch"],
                            }
                        ),
                    }
                },
            )

        provider = _local_provider_with_transport(handler)
        result = await provider.analyze_image(b"fake-bytes", "image/png")

        assert result == {
            "title": "A cat",
            "description": "A cat on a couch.",
            "ocr_text": "",
            "tags": ["cat", "couch"],
        }

    @pytest.mark.asyncio
    async def test_connect_error_becomes_a_clear_runtime_error(self):
        def handler(request: httpx.Request) -> httpx.Response:
            raise httpx.ConnectError("connection refused")

        provider = _local_provider_with_transport(handler)
        with pytest.raises(RuntimeError, match="docs/local-ai-provider-setup.md"):
            await provider.generate_text("hello")
