import asyncio

import pytest

from app.services.ai_provider import AIProvider
from app.services.collection_suggestion_service import suggest_collections


class FakeProvider(AIProvider):
    def __init__(self, name: str = "Docker Notları", *, fails: bool = False):
        self._name = name
        self._fails = fails

    async def generate_text(self, prompt, *, system=None):
        if self._fails:
            raise RuntimeError("provider down")
        return self._name

    async def generate_embedding(self, text):
        return [0.1, 0.2, 0.3]

    async def generate_embeddings(self, texts):
        return [[0.1, 0.2, 0.3] for _ in texts]


class FakeSearchRepo:
    def __init__(self, pairs: list[dict] | None = None):
        self._pairs = pairs or []
        self.last_call: dict | None = None

    async def item_similarity_pairs(self, *, similarity_threshold=0.75, max_pairs=500):
        self.last_call = {"similarity_threshold": similarity_threshold, "max_pairs": max_pairs}
        return self._pairs


def _pair(a, b, *, similarity=0.9, a_type="note", b_type="note", a_title=None, b_title=None):
    return {
        "item_a": a,
        "item_a_title": a_title or a,
        "item_a_type": a_type,
        "item_b": b,
        "item_b_title": b_title or b,
        "item_b_type": b_type,
        "similarity": similarity,
    }


@pytest.mark.asyncio
async def test_no_pairs_means_no_suggestions():
    repo = FakeSearchRepo(pairs=[])

    suggestions = await suggest_collections(repo, FakeProvider())

    assert suggestions == []


@pytest.mark.asyncio
async def test_a_chain_of_pairs_merges_into_one_cluster():
    # a~b and b~c never compares a directly to c, but should still end up
    # in the same suggested collection (transitive union-find).
    repo = FakeSearchRepo(pairs=[_pair("a", "b"), _pair("b", "c")])

    suggestions = await suggest_collections(repo, provider=None, min_group_size=3)

    assert len(suggestions) == 1
    assert {item["item_id"] for item in suggestions[0]["items"]} == {"a", "b", "c"}


@pytest.mark.asyncio
async def test_clusters_smaller_than_min_group_size_are_dropped():
    repo = FakeSearchRepo(pairs=[_pair("a", "b")])  # only a 2-item cluster

    suggestions = await suggest_collections(repo, provider=None, min_group_size=3)

    assert suggestions == []


@pytest.mark.asyncio
async def test_two_separate_clusters_stay_separate():
    repo = FakeSearchRepo(pairs=[
        _pair("a", "b"), _pair("b", "c"),  # cluster 1
        _pair("x", "y"), _pair("y", "z"),  # cluster 2
    ])

    suggestions = await suggest_collections(repo, provider=None, min_group_size=3)

    ids_per_cluster = sorted(
        tuple(sorted(item["item_id"] for item in s["items"])) for s in suggestions
    )
    assert ids_per_cluster == [("a", "b", "c"), ("x", "y", "z")]


@pytest.mark.asyncio
async def test_without_a_provider_falls_back_to_a_type_based_name():
    repo = FakeSearchRepo(pairs=[
        _pair("a", "b", a_type="pdf", b_type="pdf"),
        _pair("b", "c", a_type="pdf", b_type="pdf"),
    ])

    suggestions = await suggest_collections(repo, provider=None, min_group_size=3)

    assert suggestions[0]["suggested_name"] == "PDF Grubu (3)"


@pytest.mark.asyncio
async def test_with_a_provider_uses_the_ai_generated_name():
    repo = FakeSearchRepo(pairs=[_pair("a", "b"), _pair("b", "c")])

    suggestions = await suggest_collections(
        repo, FakeProvider(name="Docker Notları"), min_group_size=3
    )

    assert suggestions[0]["suggested_name"] == "Docker Notları"


@pytest.mark.asyncio
async def test_a_failing_provider_falls_back_instead_of_raising():
    repo = FakeSearchRepo(pairs=[_pair("a", "b"), _pair("b", "c")])

    suggestions = await suggest_collections(
        repo, FakeProvider(fails=True), min_group_size=3
    )

    assert suggestions[0]["suggested_name"] == "Not Grubu (3)"


@pytest.mark.asyncio
async def test_passes_the_similarity_threshold_through_to_the_repo():
    repo = FakeSearchRepo(pairs=[])

    await suggest_collections(repo, provider=None, similarity_threshold=0.8)

    assert repo.last_call["similarity_threshold"] == 0.8


class _ConcurrencyTrackingProvider(AIProvider):
    """Records how many `generate_text` calls were in flight at once —
    regression guard for `suggest_collections` naming clusters
    concurrently rather than one at a time.
    """

    def __init__(self) -> None:
        self.active = 0
        self.max_active = 0

    async def generate_text(self, prompt, *, system=None):
        self.active += 1
        self.max_active = max(self.max_active, self.active)
        await asyncio.sleep(0)  # yield so overlapping calls actually interleave
        self.active -= 1
        return "Name"

    async def generate_embedding(self, text):
        return [0.1, 0.2, 0.3]

    async def generate_embeddings(self, texts):
        return [[0.1, 0.2, 0.3] for _ in texts]


@pytest.mark.asyncio
async def test_naming_calls_for_separate_clusters_run_concurrently():
    repo = FakeSearchRepo(pairs=[
        _pair("a", "b"), _pair("b", "c"),  # cluster 1
        _pair("x", "y"), _pair("y", "z"),  # cluster 2
    ])
    provider = _ConcurrencyTrackingProvider()

    suggestions = await suggest_collections(repo, provider, min_group_size=3)

    assert len(suggestions) == 2
    assert provider.max_active >= 2
