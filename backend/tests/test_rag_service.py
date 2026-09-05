import pytest

from app.services.ai_provider import AIProvider
from app.services.rag_service import answer_question


class FakeProvider(AIProvider):
    def __init__(self):
        self.last_prompt = None
        self.last_system = None

    async def generate_text(self, prompt, *, system=None):
        self.last_prompt = prompt
        self.last_system = system
        return "Docker Compose birden fazla container'ı yönetmeni sağlar. [Kaynak 1]"

    async def generate_embedding(self, text):
        return [0.1, 0.2, 0.3]

    async def generate_embeddings(self, texts):
        return [[0.1, 0.2, 0.3] for _ in texts]


class FakeSearchRepo:
    def __init__(self, matches):
        self._matches = matches

    async def match_chunks(self, query_embedding, *, match_count=40):
        return self._matches


@pytest.mark.asyncio
async def test_answers_using_retrieved_sources():
    repo = FakeSearchRepo(
        [
            {
                "item_id": "note-1",
                "item_type": "note",
                "item_title": "Docker Notes",
                "content": "Docker Compose lets you define multi-container apps.",
                "similarity": 0.9,
            }
        ]
    )
    provider = FakeProvider()

    result = await answer_question("Docker compose nedir?", repo, provider)

    assert "Docker Compose" in result["answer"]
    assert len(result["sources"]) == 1
    assert result["sources"][0]["item_id"] == "note-1"
    # The retrieved chunk actually made it into the prompt sent to the LLM.
    assert "Docker Compose lets you define multi-container apps." in provider.last_prompt
    assert "Kaynak 1" in provider.last_prompt


@pytest.mark.asyncio
async def test_no_matches_short_circuits_without_calling_the_llm():
    repo = FakeSearchRepo([])
    provider = FakeProvider()

    result = await answer_question("alakasız bir soru", repo, provider)

    assert result["sources"] == []
    assert "bulamadım" in result["answer"].lower()
    assert provider.last_prompt is None  # never called generate_text — saved a completion


@pytest.mark.asyncio
async def test_system_prompt_forbids_answering_outside_the_sources():
    repo = FakeSearchRepo(
        [
            {
                "item_id": "a",
                "item_type": "note",
                "item_title": "A",
                "content": "x",
                "similarity": 0.5,
            }
        ]
    )
    provider = FakeProvider()

    await answer_question("soru", repo, provider)

    assert provider.last_system is not None
    assert "only" in provider.last_system.lower() or "yalnız" in provider.last_system.lower()
