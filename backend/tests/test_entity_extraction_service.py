import pytest

from app.services.ai_provider import AIProvider
from app.services.entity_extraction_service import extract_entities


class FakeProvider(AIProvider):
    provider_name = "fake"

    def __init__(self, response: str = "person: Ahmet Yılmaz", *, fails: bool = False):
        self._response = response
        self._fails = fails
        self.last_prompt: str | None = None

    @property
    def embedding_model(self):
        return "fake-embedding-model"

    async def generate_text(self, prompt, *, system=None):
        self.last_prompt = prompt
        if self._fails:
            raise RuntimeError("provider down")
        return self._response

    async def generate_embedding(self, text):
        return [0.1, 0.2, 0.3]

    async def generate_embeddings(self, texts):
        return [[0.1, 0.2, 0.3] for _ in texts]


@pytest.mark.asyncio
async def test_parses_type_colon_name_lines():
    response = "person: Ahmet Yılmaz\nplace: İstanbul\ndate: 15 Ocak 2026"

    entities = await extract_entities("some text", FakeProvider(response))

    assert entities == [
        {"name": "Ahmet Yılmaz", "type": "person"},
        {"name": "İstanbul", "type": "place"},
        {"name": "15 Ocak 2026", "type": "date"},
    ]


@pytest.mark.asyncio
async def test_empty_text_never_calls_the_provider():
    entities = await extract_entities("   ", FakeProvider())

    assert entities == []


@pytest.mark.asyncio
async def test_a_failing_provider_yields_an_empty_list_not_an_exception():
    entities = await extract_entities("some text", FakeProvider(fails=True))

    assert entities == []


@pytest.mark.asyncio
async def test_skips_lines_with_no_colon_or_an_unknown_type():
    response = "person: Ahmet\njust a stray sentence\nplanet: Mars\norganization: Acme Corp"

    entities = await extract_entities("some text", FakeProvider(response))

    assert entities == [
        {"name": "Ahmet", "type": "person"},
        {"name": "Acme Corp", "type": "organization"},
    ]


@pytest.mark.asyncio
async def test_dedupes_case_insensitively_and_caps_at_max_entities():
    response = "person: Ahmet\nperson: ahmet\nperson: AHMET\nplace: İstanbul\ndate: 2026-01-15"

    entities = await extract_entities("some text", FakeProvider(response), max_entities=2)

    # Keeps first-seen casing, dedupes the repeats, caps at max_entities.
    assert entities == [
        {"name": "Ahmet", "type": "person"},
        {"name": "İstanbul", "type": "place"},
    ]


@pytest.mark.asyncio
async def test_the_same_name_with_different_types_is_kept_separately():
    response = "organization: Washington\nplace: Washington"

    entities = await extract_entities("some text", FakeProvider(response))

    assert entities == [
        {"name": "Washington", "type": "organization"},
        {"name": "Washington", "type": "place"},
    ]


# P3 (docs/requirements-audit-2026-09-13.md): product/price/website/
# technology added to the original person/place/organization/date set —
# see 0020_entity_types_extend.sql for the matching check constraint.
@pytest.mark.asyncio
async def test_parses_the_four_newly_added_types():
    response = (
        "product: iPhone 17 Pro\n"
        "price: 1200 TL\n"
        "website: github.com\n"
        "technology: Flutter"
    )

    entities = await extract_entities("some text", FakeProvider(response))

    assert entities == [
        {"name": "iPhone 17 Pro", "type": "product"},
        {"name": "1200 TL", "type": "price"},
        {"name": "github.com", "type": "website"},
        {"name": "Flutter", "type": "technology"},
    ]


# P3 (docs/requirements-audit-2026-09-13.md): the prompt used to end with
# a few-shot example whose realistic-looking values ("İstanbul", "Ahmet
# Yılmaz", a date) a weaker/local model could echo back as if they'd
# actually been extracted from the input — confirmed live on a flower
# photo with none of those things anywhere in its description.
@pytest.mark.asyncio
async def test_prompt_has_no_example_values_a_weak_model_could_echo():
    provider = FakeProvider()

    await extract_entities("some text", provider)

    assert provider.last_prompt is not None
    assert "İstanbul" not in provider.last_prompt
    assert "Ahmet Yılmaz" not in provider.last_prompt
    assert "uydurma" in provider.last_prompt
    assert "boş" in provider.last_prompt
