"""P3 (docs/requirements-audit-2026-09-13.md): reembedding_service.py —
the on-request fix for chunks left behind by an AI_PROVIDER/model switch.
"""

import pytest

from app.services.ai_provider import AIProvider
from app.services.reembedding_service import reembed_stale_items


class FakeProvider(AIProvider):
    provider_name = "local"

    def __init__(self, *, fails_on: str | None = None):
        self._fails_on = fails_on
        self.embed_calls: list[list[str]] = []

    @property
    def embedding_model(self):
        return "nomic-embed-text"

    async def generate_text(self, prompt, *, system=None):
        raise NotImplementedError

    async def generate_embedding(self, text):
        raise NotImplementedError

    async def generate_embeddings(self, texts):
        if self._fails_on and self._fails_on in texts:
            raise RuntimeError("provider down")
        self.embed_calls.append(texts)
        return [[0.9, 0.8, 0.7] for _ in texts]


class FakeRepo:
    def __init__(self, *, stale_item_ids, chunks_by_item_id):
        self._stale_item_ids = stale_item_ids
        self._chunks_by_item_id = chunks_by_item_id
        self.find_stale_calls: list[tuple[str, str]] = []
        self.create_job_calls: list[str] = []
        self.replace_chunks_calls: list[tuple[str, str, list[dict]]] = []
        self._job_counter = 0

    async def find_stale_chunk_item_ids(self, current_provider, current_embedding_model):
        self.find_stale_calls.append((current_provider, current_embedding_model))
        return self._stale_item_ids

    async def get_chunks_for_item(self, item_id):
        return self._chunks_by_item_id.get(item_id, [])

    async def create_job(self, item_id, job_type):
        self._job_counter += 1
        self.create_job_calls.append(item_id)
        assert job_type == "reembed"
        return f"job-{self._job_counter}"

    async def replace_chunks(self, item_id, job_id, chunks):
        self.replace_chunks_calls.append((item_id, job_id, chunks))


@pytest.mark.asyncio
async def test_re_embeds_every_stale_item_and_reports_how_many():
    repo = FakeRepo(
        stale_item_ids=["item-1", "item-2"],
        chunks_by_item_id={
            "item-1": [{"chunk_index": 0, "content": "Docker notes", "metadata": {}}],
            "item-2": [{"chunk_index": 0, "content": "Riverpod notes", "metadata": {}}],
        },
    )
    provider = FakeProvider()

    count = await reembed_stale_items(repo, provider)

    assert count == 2
    assert repo.find_stale_calls == [("local", "nomic-embed-text")]
    assert len(repo.replace_chunks_calls) == 2


@pytest.mark.asyncio
async def test_checks_against_the_currently_configured_provider_and_model():
    repo = FakeRepo(stale_item_ids=[], chunks_by_item_id={})
    provider = FakeProvider()

    await reembed_stale_items(repo, provider)

    assert repo.find_stale_calls == [("local", "nomic-embed-text")]


@pytest.mark.asyncio
async def test_the_new_chunk_rows_carry_the_current_provider_and_preserve_content_and_metadata():
    repo = FakeRepo(
        stale_item_ids=["item-1"],
        chunks_by_item_id={
            "item-1": [
                {"chunk_index": 0, "content": "Page one text", "metadata": {"page_number": 1}},
                {"chunk_index": 1, "content": "Page two text", "metadata": {"page_number": 2}},
            ],
        },
    )
    provider = FakeProvider()

    await reembed_stale_items(repo, provider)

    item_id, job_id, chunks = repo.replace_chunks_calls[0]
    assert item_id == "item-1"
    assert job_id == "job-1"
    assert [c["content"] for c in chunks] == ["Page one text", "Page two text"]
    assert [c["metadata"] for c in chunks] == [{"page_number": 1}, {"page_number": 2}]
    assert all(c["embedding_provider"] == "local" for c in chunks)
    assert all(c["embedding_model"] == "nomic-embed-text" for c in chunks)
    assert all(c["embedding"] == "[0.9,0.8,0.7]" for c in chunks)


@pytest.mark.asyncio
async def test_an_item_with_no_chunks_left_is_skipped_without_creating_a_job():
    repo = FakeRepo(stale_item_ids=["item-gone"], chunks_by_item_id={})
    provider = FakeProvider()

    count = await reembed_stale_items(repo, provider)

    assert count == 1  # counted as "handled", nothing left to actually do
    assert repo.create_job_calls == []
    assert repo.replace_chunks_calls == []


@pytest.mark.asyncio
async def test_one_items_failure_does_not_stop_the_rest_from_being_reembedded():
    repo = FakeRepo(
        stale_item_ids=["item-bad", "item-good"],
        chunks_by_item_id={
            "item-bad": [{"chunk_index": 0, "content": "boom", "metadata": {}}],
            "item-good": [{"chunk_index": 0, "content": "fine", "metadata": {}}],
        },
    )
    provider = FakeProvider(fails_on="boom")

    count = await reembed_stale_items(repo, provider)

    assert count == 1  # only item-good succeeded
    assert repo.replace_chunks_calls[0][0] == "item-good"


@pytest.mark.asyncio
async def test_nothing_stale_re_embeds_nothing():
    repo = FakeRepo(stale_item_ids=[], chunks_by_item_id={})
    provider = FakeProvider()

    count = await reembed_stale_items(repo, provider)

    assert count == 0
    assert repo.replace_chunks_calls == []
