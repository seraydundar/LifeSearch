import pytest

from app.services.ai_provider import AIProvider
from app.services.search_service import find_related_items, semantic_search


class FakeProvider(AIProvider):
    provider_name = "fake"

    def __init__(self, rerank_response: str = "fake"):
        # "fake" deliberately parses into zero usable indices (see
        # reranking_service._parse_order), so every pre-existing test in
        # this file that doesn't care about reranking keeps seeing the
        # plain RRF/dedupe order — rerank_matches falls back to it.
        self._rerank_response = rerank_response
        self.generate_text_calls = 0

    @property
    def embedding_model(self):
        return "fake-embedding-model"

    async def generate_text(self, prompt, *, system=None):
        self.generate_text_calls += 1
        return self._rerank_response

    async def generate_embedding(self, text):
        return [0.1, 0.2, 0.3]

    async def generate_embeddings(self, texts):
        return [[0.1, 0.2, 0.3] for _ in texts]


class FakeSearchRepo:
    def __init__(self, matches=None, related=None):
        self._matches = matches or []
        self._related = related or []
        self.last_hybrid_call = None
        self.last_related_call = None

    async def match_chunks_hybrid(self, query_embedding, query_text, *, match_count=40, **filters):
        self.last_hybrid_call = {
            "query_embedding": query_embedding,
            "query_text": query_text,
            "match_count": match_count,
            **filters,
        }
        return self._matches

    async def related_items(self, item_id, *, match_count=12, include_private=False):
        self.last_related_call = {
            "item_id": item_id,
            "match_count": match_count,
            "include_private": include_private,
        }
        return self._related


@pytest.mark.asyncio
async def test_dedupes_to_the_best_matching_chunk_per_item():
    repo = FakeSearchRepo(
        [
            {
                "item_id": "a",
                "item_type": "note",
                "item_title": "A",
                "content": "weak",
                "score": 0.4,
            },
            {
                "item_id": "a",
                "item_type": "note",
                "item_title": "A",
                "content": "strong",
                "score": 0.9,
            },
            {"item_id": "b", "item_type": "pdf", "item_title": "B", "content": "mid", "score": 0.6},
        ]
    )

    results = await semantic_search("query", repo, FakeProvider(), limit=10)

    assert [r["item_id"] for r in results] == ["a", "b"]
    assert results[0]["content"] == "strong"  # the better of item a's two chunks


@pytest.mark.asyncio
async def test_results_are_ranked_by_score_descending():
    repo = FakeSearchRepo(
        [
            {
                "item_id": "low",
                "item_type": "note",
                "item_title": None,
                "content": "x",
                "score": 0.2,
            },
            {
                "item_id": "high",
                "item_type": "note",
                "item_title": None,
                "content": "y",
                "score": 0.8,
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
                "score": i / 10,
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

    assert repo.last_hybrid_call["match_count"] > 10


@pytest.mark.asyncio
async def test_passes_metadata_filters_through_to_the_repository():
    repo = FakeSearchRepo([])

    await semantic_search(
        "query",
        repo,
        FakeProvider(),
        item_types=["note", "pdf"],
    )

    assert repo.last_hybrid_call["item_types"] == ["note", "pdf"]


@pytest.mark.asyncio
async def test_excludes_private_items_by_default():
    """P1-02 (docs/requirements-audit-2026-09-13.md): private items are
    excluded in SQL by default — the repository call must say so rather
    than relying on a client-side filter after the content already left
    the server.
    """
    repo = FakeSearchRepo([])

    await semantic_search("query", repo, FakeProvider())

    assert repo.last_hybrid_call["include_private"] is False


@pytest.mark.asyncio
async def test_include_private_is_forwarded_when_reveal_is_on():
    repo = FakeSearchRepo([])

    await semantic_search("query", repo, FakeProvider(), include_private=True)

    assert repo.last_hybrid_call["include_private"] is True


@pytest.mark.asyncio
async def test_passes_the_current_providers_identity_through_for_embedding_provenance():
    """P3 (docs/requirements-audit-2026-09-13.md): a query's embedding must
    never be compared against a chunk from a different provider/model's
    vector space — match_chunks_hybrid needs to know which one is "current"
    to exclude a mismatch (see 0023_hybrid_search_embedding_provenance.sql).
    """
    repo = FakeSearchRepo([])

    await semantic_search("query", repo, FakeProvider())

    assert repo.last_hybrid_call["embedding_provider"] == "fake"
    assert repo.last_hybrid_call["embedding_model"] == "fake-embedding-model"


@pytest.mark.asyncio
async def test_related_items_dedupes_and_ranks_by_similarity():
    repo = FakeSearchRepo(
        related=[
            {
                "item_id": "x",
                "item_type": "note",
                "item_title": "X",
                "content": "a",
                "similarity": 0.3,
            },
            {
                "item_id": "y",
                "item_type": "note",
                "item_title": "Y",
                "content": "b",
                "similarity": 0.9,
            },
        ]
    )

    results = await find_related_items("source-item", repo, limit=5)

    assert [r["item_id"] for r in results] == ["y", "x"]
    assert repo.last_related_call["item_id"] == "source-item"
    assert repo.last_related_call["include_private"] is False


@pytest.mark.asyncio
async def test_reranking_can_promote_an_item_the_raw_rrf_order_would_have_cut():
    """The shortlist handed to the reranker is wider than the final
    `limit` — otherwise reranking could only ever reorder a list RRF
    already cut down to size, never actually change which items make it.
    """
    repo = FakeSearchRepo(
        [
            {
                "item_id": str(i),
                "item_type": "note",
                "item_title": None,
                "content": "x",
                "score": i / 10,
            }
            for i in range(10)
        ]
    )
    # Plain RRF/dedupe order (desc by score) is 9,8,7,6,5,4,3,2,1,0 — with
    # limit=3 that would return [9,8,7]. The shortlist widens to
    # limit*2=6 items (9,8,7,6,5,4); this response ranks the 6th of those
    # ("4", position 6 — never would have survived a plain limit=3) first.
    provider = FakeProvider(rerank_response="6,1,2,3,4,5")

    results = await semantic_search("query", repo, provider, limit=3)

    assert [r["item_id"] for r in results] == ["4", "9", "8"]


@pytest.mark.asyncio
async def test_rerank_false_skips_the_llm_call_and_keeps_the_rrf_order():
    repo = FakeSearchRepo(
        [
            {
                "item_id": "low",
                "item_type": "note",
                "item_title": None,
                "content": "x",
                "score": 0.2,
            },
            {
                "item_id": "high",
                "item_type": "note",
                "item_title": None,
                "content": "y",
                "score": 0.8,
            },
        ]
    )
    provider = FakeProvider(rerank_response="2,1")  # would flip the order if it were used

    results = await semantic_search("query", repo, provider, limit=10, rerank=False)

    assert [r["item_id"] for r in results] == ["high", "low"]
    assert provider.generate_text_calls == 0
