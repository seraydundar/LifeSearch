import pytest

from app.core.config import Settings
from app.services.ai_provider import GeminiProvider, OpenAIProvider, _pad_embedding, get_ai_provider


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


def test_local_provider_is_not_implemented_yet():
    with pytest.raises(NotImplementedError):
        get_ai_provider(Settings(ai_provider="local"))


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
