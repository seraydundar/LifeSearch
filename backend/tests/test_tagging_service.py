import pytest

from app.services.ai_provider import AIProvider
from app.services.tagging_service import generate_tags


class FakeProvider(AIProvider):
    provider_name = "fake"

    def __init__(self, response: str = "docker, container, devops", *, fails: bool = False):
        self._response = response
        self._fails = fails

    @property
    def embedding_model(self):
        return "fake-embedding-model"

    async def generate_text(self, prompt, *, system=None):
        if self._fails:
            raise RuntimeError("provider down")
        return self._response

    async def generate_embedding(self, text):
        return [0.1, 0.2, 0.3]

    async def generate_embeddings(self, texts):
        return [[0.1, 0.2, 0.3] for _ in texts]


@pytest.mark.asyncio
async def test_parses_a_comma_separated_response():
    tags = await generate_tags("Docker container ile image arasındaki fark.", FakeProvider())

    assert tags == ["docker", "container", "devops"]


@pytest.mark.asyncio
async def test_empty_text_never_calls_the_provider():
    tags = await generate_tags("   ", FakeProvider())

    assert tags == []


@pytest.mark.asyncio
async def test_a_failing_provider_yields_an_empty_list_not_an_exception():
    tags = await generate_tags("some text", FakeProvider(fails=True))

    assert tags == []


@pytest.mark.asyncio
async def test_dedupes_and_caps_at_max_tags():
    provider = FakeProvider(response="docker, Docker, docker , container, image, cloud, devops")

    tags = await generate_tags("text", provider, max_tags=3)

    assert tags == ["docker", "container", "image"]


@pytest.mark.asyncio
async def test_handles_newline_separated_responses_too():
    provider = FakeProvider(response="docker\ncontainer\ndevops")

    tags = await generate_tags("text", provider)

    assert tags == ["docker", "container", "devops"]
