import pytest

from app.services.ai_provider import AIProvider
from app.services.reranking_service import rerank_matches


class _StubProvider(AIProvider):
    def __init__(self, response: str | Exception):
        self._response = response

    async def generate_text(self, prompt, *, system=None):
        if isinstance(self._response, Exception):
            raise self._response
        return self._response

    async def generate_embedding(self, text):
        raise NotImplementedError

    async def generate_embeddings(self, texts):
        raise NotImplementedError


def _match(item_id: str, content: str = "x") -> dict:
    return {"item_id": item_id, "item_type": "note", "item_title": item_id, "content": content}


@pytest.mark.asyncio
async def test_zero_or_one_candidates_never_call_the_provider():
    provider = _StubProvider(RuntimeError("should never be called"))

    assert await rerank_matches("q", [], provider, limit=5) == []
    one = [_match("a")]
    assert await rerank_matches("q", one, provider, limit=5) == one


@pytest.mark.asyncio
async def test_reorders_candidates_per_the_models_ranking():
    matches = [_match("a"), _match("b"), _match("c")]
    provider = _StubProvider("3,1,2")  # c, a, b

    result = await rerank_matches("q", matches, provider, limit=3)

    assert [m["item_id"] for m in result] == ["c", "a", "b"]


@pytest.mark.asyncio
async def test_narrows_down_to_the_requested_limit():
    matches = [_match(str(i)) for i in range(5)]
    provider = _StubProvider("5,4,3,2,1")

    result = await rerank_matches("q", matches, provider, limit=2)

    assert [m["item_id"] for m in result] == ["4", "3"]


@pytest.mark.asyncio
async def test_a_provider_error_falls_back_to_the_original_order():
    matches = [_match("a"), _match("b")]
    provider = _StubProvider(RuntimeError("no api key"))

    result = await rerank_matches("q", matches, provider, limit=2)

    assert [m["item_id"] for m in result] == ["a", "b"]


@pytest.mark.asyncio
async def test_unparseable_response_falls_back_to_the_original_order():
    matches = [_match("a"), _match("b"), _match("c")]
    provider = _StubProvider("Sure, here are the results you asked for!")

    result = await rerank_matches("q", matches, provider, limit=3)

    assert [m["item_id"] for m in result] == ["a", "b", "c"]


@pytest.mark.asyncio
async def test_a_ranking_that_only_mentions_one_of_several_is_treated_as_unusable():
    """Mentioning far fewer candidates than it was given reads as a
    misfire (stray digit in prose), not a genuine partial ranking.
    """
    matches = [_match(str(i)) for i in range(6)]
    provider = _StubProvider("Number 1 looks best.")

    result = await rerank_matches("q", matches, provider, limit=6)

    assert [m["item_id"] for m in result] == [str(i) for i in range(6)]


@pytest.mark.asyncio
async def test_a_partial_ranking_appends_unmentioned_candidates_in_original_order():
    matches = [_match("a"), _match("b"), _match("c"), _match("d")]
    provider = _StubProvider("3,1")  # only mentions half — exactly the cutoff, still usable

    result = await rerank_matches("q", matches, provider, limit=4)

    assert [m["item_id"] for m in result] == ["c", "a", "b", "d"]


@pytest.mark.asyncio
async def test_duplicate_and_out_of_range_numbers_in_the_response_are_ignored():
    matches = [_match("a"), _match("b"), _match("c")]
    provider = _StubProvider("2,2,99,1,3")

    result = await rerank_matches("q", matches, provider, limit=3)

    assert [m["item_id"] for m in result] == ["b", "a", "c"]


@pytest.mark.asyncio
async def test_more_than_the_internal_candidate_cap_only_reranks_the_head():
    from app.services import reranking_service

    matches = [_match(str(i)) for i in range(reranking_service._MAX_CANDIDATES + 10)]
    provider = _StubProvider("1,2,3")

    result = await rerank_matches("q", matches, provider, limit=100)

    assert len(result) == reranking_service._MAX_CANDIDATES
