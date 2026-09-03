import pytest

from app.core.config import Settings
from app.services.ai_provider import OpenAIProvider, get_ai_provider


def test_openai_provider_selected_when_configured():
    settings = Settings(ai_provider="openai", openai_api_key="sk-test")
    provider = get_ai_provider(settings)
    assert isinstance(provider, OpenAIProvider)


def test_openai_without_a_key_raises_a_clear_error():
    settings = Settings(ai_provider="openai", openai_api_key="")
    with pytest.raises(RuntimeError, match="OPENAI_API_KEY"):
        get_ai_provider(settings)


def test_unimplemented_providers_fail_loudly_not_silently():
    with pytest.raises(NotImplementedError):
        get_ai_provider(Settings(ai_provider="gemini"))
    with pytest.raises(NotImplementedError):
        get_ai_provider(Settings(ai_provider="local"))


def test_unknown_provider_name_is_rejected():
    with pytest.raises(ValueError, match="Unknown AI_PROVIDER"):
        get_ai_provider(Settings(ai_provider="not-a-real-provider"))
