import pytest

from app.services.ai_provider import AIProvider
from app.services.search_service import semantic_search


class FakeProvider(AIProvider):
    async def generate_text(self, prompt, *, system=None):
        return "fake"

    async def generate_embedding(self, text):
        return [0.1, 0.2, 0.3]

    async def generate_embeddings(self, texts):
        return [[0.1, 0.2, 0.3] for _ in texts]


class FakeSearchRepo:
    def __init__(self, matches):
        self._matches = matches
        self.last_call = None

    async def match_chunks(self, query_embedding, *, match_count=40):
        self.last_call = {"query_embedding": query_embedding, "match_count": match_count}
        return self._matches


@pytest.mark.asyncio
async def test_dedupes_to_the_best_matching_chunk_per_item():
    repo = FakeSearchRepo(
        [
            {
                "item_id": "a",
                "item_type": "note",
                "item_title": "A",
                "content": "weak",
                "similarity": 0.4,
            },
            {
                "item_id": "a",
                "item_type": "note",
                "item_title": "A",
                "content": "strong",
                "similarity": 0.9,
            },
            {
                "item_id": "b",
                "item_type": "pdf",
                "item_title": "B",
                "content": "mid",
                "similarity": 0.6,
            },
        ]
    )

    results = await semantic_search("query", repo, FakeProvider(), limit=10)

    assert [r["item_id"] for r in results] == ["a", "b"]
    assert results[0]["content"] == "strong"  # the better of item a's two chunks


@pytest.mark.asyncio
async def test_results_are_ranked_by_similarity_descending():
    repo = FakeSearchRepo(
        [
            {
                "item_id": "low",
                "item_type": "note",
                "item_title": None,
                "content": "x",
                "similarity": 0.2,
            },
            {
                "item_id": "high",
                "item_type": "note",
                "item_title": None,
                "content": "y",
                "similarity": 0.8,
            },
        ]
    )

    results = await semantic_search("query", repo, FakeProvider(), limit=10)

    assert [r["item_id"] for r in results] == ["high", "low"]


@pytest.mark.asyncio
async def test_respects_the_limit_after_deduping():
    repo = FakeSearchRepo(
        [
            {
                "item_id": str(i),
                "item_type": "note",
                "item_title": None,
                "content": "x",
                "similarity": i / 10,
            }
            for i in range(10)
        ]
    )

    results = await semantic_search("query", repo, FakeProvider(), limit=3)

    assert len(results) == 3
    assert [r["item_id"] for r in results] == ["9", "8", "7"]


@pytest.mark.asyncio
async def test_over_fetches_more_chunks_than_the_requested_item_limit():
    repo = FakeSearchRepo([])

    await semantic_search("query", repo, FakeProvider(), limit=10)

    assert repo.last_call["match_count"] > 10
