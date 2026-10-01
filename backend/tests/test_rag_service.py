import pytest

from app.services.ai_provider import AIProvider
from app.services.rag_service import answer_question


class FakeProvider(AIProvider):
    provider_name = "fake"

    def __init__(self):
        self.last_prompt = None
        self.last_system = None
        self.embedding_calls: list[str] = []

    @property
    def embedding_model(self):
        return "fake-embedding-model"

    async def generate_text(self, prompt, *, system=None):
        self.last_prompt = prompt
        self.last_system = system
        return "Docker Compose birden fazla container'ı yönetmeni sağlar. [Kaynak 1]"

    async def generate_embedding(self, text):
        self.embedding_calls.append(text)
        return [0.1, 0.2, 0.3]

    async def generate_embeddings(self, texts):
        return [[0.1, 0.2, 0.3] for _ in texts]


class FakeSearchRepo:
    def __init__(self, matches):
        self._matches = matches
        self.last_hybrid_call_filters = None

    async def match_chunks_hybrid(self, query_embedding, query_text, *, match_count=40, **filters):
        self.last_hybrid_call_filters = filters
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
                "score": 0.9,
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
                "score": 0.5,
            }
        ]
    )
    provider = FakeProvider()

    await answer_question("soru", repo, provider)

    assert provider.last_system is not None
    assert "only" in provider.last_system.lower() or "yalnız" in provider.last_system.lower()


# P2-03 (docs/requirements-audit-2026-09-13.md): a follow-up question
# ("peki onun alternatifi ne?") used to be answered with zero awareness
# that any earlier turn in the conversation existed.
class TestConversationHistory:
    @pytest.mark.asyncio
    async def test_includes_prior_turns_in_the_prompt(self):
        repo = FakeSearchRepo(
            [{"item_id": "a", "item_type": "note", "item_title": "A", "content": "x", "score": 0.5}]
        )
        provider = FakeProvider()

        await answer_question(
            "peki onun alternatifi ne?",
            repo,
            provider,
            history=[
                {"role": "user", "text": "Docker compose nedir?"},
                {"role": "assistant", "text": "Docker Compose çoklu container yönetir."},
            ],
        )

        assert "Docker compose nedir?" in provider.last_prompt
        assert "Docker Compose çoklu container yönetir." in provider.last_prompt
        # The actual new question is still there too, not replaced by history.
        assert "peki onun alternatifi ne?" in provider.last_prompt

    @pytest.mark.asyncio
    async def test_no_history_omits_the_history_section(self):
        repo = FakeSearchRepo(
            [{"item_id": "a", "item_type": "note", "item_title": "A", "content": "x", "score": 0.5}]
        )
        provider = FakeProvider()

        await answer_question("soru", repo, provider)

        assert "Önceki konuşma" not in provider.last_prompt

    @pytest.mark.asyncio
    async def test_history_never_used_for_retrieval_only_for_the_prompt(self):
        """Retrieval still searches on the new question alone — history
        widens what the model can resolve ("onun" -> the last topic), not
        what gets embedded and searched for.
        """
        repo = FakeSearchRepo(
            [{"item_id": "a", "item_type": "note", "item_title": "A", "content": "x", "score": 0.5}]
        )
        provider = FakeProvider()

        await answer_question(
            "peki onun boyu?",
            repo,
            provider,
            history=[{"role": "user", "text": "Eyfel Kulesi ne zaman yapıldı?"}],
        )

        assert provider.embedding_calls == ["peki onun boyu?"]

    @pytest.mark.asyncio
    async def test_history_is_capped_to_the_most_recent_turns(self):
        repo = FakeSearchRepo(
            [{"item_id": "a", "item_type": "note", "item_title": "A", "content": "x", "score": 0.5}]
        )
        provider = FakeProvider()
        long_history = [
            {"role": "user", "text": f"soru {i}"} for i in range(20)
        ]

        await answer_question("son soru", repo, provider, history=long_history)

        assert "soru 0" not in provider.last_prompt  # old enough to be dropped
        assert "soru 19" in provider.last_prompt  # most recent, kept


@pytest.mark.asyncio
async def test_never_requests_private_items():
    """P1-02 (docs/requirements-audit-2026-09-13.md): chat has no private
    reveal concept, so it must never ask retrieval to include private
    items, unrevealed or not.
    """
    repo = FakeSearchRepo([])
    provider = FakeProvider()

    await answer_question("soru", repo, provider)

    assert repo.last_hybrid_call_filters["include_private"] is False


class _ScriptedProvider(AIProvider):
    """Unlike `FakeProvider`, returns whatever answer text the test
    gives it — needed to exercise `_cited_sources`'s filtering against
    more than one fixed canned response.
    """

    provider_name = "fake"

    def __init__(self, answer: str):
        self._answer = answer

    @property
    def embedding_model(self):
        return "fake-embedding-model"

    async def generate_text(self, prompt, *, system=None):
        return self._answer

    async def generate_embedding(self, text):
        return [0.1, 0.2, 0.3]

    async def generate_embeddings(self, texts):
        return [[0.1, 0.2, 0.3] for _ in texts]


def _match(item_id: str) -> dict:
    return {
        "item_id": item_id,
        "item_type": "note",
        "item_title": item_id,
        "content": "x",
        "score": 0.5,
    }


class TestCitedSourcesOnly:
    """`sources`'ın kendi sözleşmesi (bkz. mobile/.../chat_message.dart):
    cevabın GERÇEKTEN geldiği item'lar. Daha önce context'e giren HER
    match, cevap metninde hiç geçmese bile "Sources" olarak dönüyordu —
    bir Docker notuyla ilgili soruya alakasız fotoğraflar/sesli not
    kaynak gibi görünebiliyordu (canlı doğrulandı)."""

    @pytest.mark.asyncio
    async def test_only_the_cited_match_is_returned_as_a_source(self):
        repo = FakeSearchRepo([_match("a"), _match("b"), _match("c")])
        provider = _ScriptedProvider("Cevap burada. [Kaynak 1]")

        result = await answer_question("soru", repo, provider)

        assert [m["item_id"] for m in result["sources"]] == ["a"]

    @pytest.mark.asyncio
    async def test_multiple_citations_keep_the_original_relevance_order(self):
        repo = FakeSearchRepo([_match("a"), _match("b"), _match("c")])
        # Cites 1 and 3 — in the opposite order they appear in the text —
        # the returned sources must still follow `matches`' own order.
        provider = _ScriptedProvider("Önce [Kaynak 3], sonra [Kaynak 1] de aynı şeyi söylüyor.")

        result = await answer_question("soru", repo, provider)

        assert [m["item_id"] for m in result["sources"]] == ["a", "c"]

    @pytest.mark.asyncio
    async def test_an_answer_with_no_citation_falls_back_to_every_match(self):
        """A weaker model ignoring the citation instruction shouldn't
        make sources *disappear* — that would hide items nobody
        confirmed were actually irrelevant.
        """
        repo = FakeSearchRepo([_match("a"), _match("b")])
        provider = _ScriptedProvider("Bu konuda bilgi bulamadım.")

        result = await answer_question("soru", repo, provider)

        assert [m["item_id"] for m in result["sources"]] == ["a", "b"]

    @pytest.mark.asyncio
    async def test_a_hallucinated_out_of_range_citation_is_ignored_not_a_crash(self):
        repo = FakeSearchRepo([_match("a")])
        provider = _ScriptedProvider("Cevap. [Kaynak 1] [Kaynak 99]")

        result = await answer_question("soru", repo, provider)

        assert [m["item_id"] for m in result["sources"]] == ["a"]
