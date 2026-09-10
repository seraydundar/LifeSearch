"""HTTP-level regression tests for the idempotent-replace fix (Faz 10b,
madde 3 — see docs/roadmap.md). `replace_chunks`/`replace_item_content`
used to issue an independent DELETE followed by an independent INSERT;
the actual bug (two concurrent reprocessing runs doubling every chunk)
only shows up at the HTTP-request level, which the pipeline-level fakes
elsewhere (see test_processing_pipeline.py's `FakeRepo`) stand in for
and so can't see — these construct a real `SupabaseRestRepository` and
intercept its requests with `httpx.MockTransport` instead of hitting a
real database.
"""

import httpx
import pytest

from app.repositories.items_repository import SupabaseRestRepository


def _repo_with_transport(handler) -> SupabaseRestRepository:
    repo = SupabaseRestRepository("test-token")
    # Swap in a transport that never touches the network, after
    # construction, so the repository is built exactly the way
    # production code builds it (real headers, real base_url handling).
    repo._client = httpx.AsyncClient(headers=repo._headers, transport=httpx.MockTransport(handler))
    return repo


@pytest.mark.asyncio
async def test_replace_chunks_upserts_instead_of_delete_then_insert():
    requests: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        return httpx.Response(201 if request.method == "POST" else 204)

    repo = _repo_with_transport(handler)
    try:
        await repo.replace_chunks(
            "item-1",
            [
                {
                    "item_id": "item-1",
                    "content": "a",
                    "chunk_index": 0,
                    "embedding": "[0]",
                    "metadata": {},
                },
                {
                    "item_id": "item-1",
                    "content": "b",
                    "chunk_index": 1,
                    "embedding": "[0]",
                    "metadata": {},
                },
            ],
        )
    finally:
        await repo.aclose()

    # Exactly one upsert POST, not a DELETE-then-INSERT pair.
    assert [r.method for r in requests] == ["POST", "DELETE"]
    upsert, trim = requests

    assert upsert.url.params["on_conflict"] == "item_id,chunk_index"
    assert upsert.headers["prefer"] == "resolution=merge-duplicates,return=minimal"

    # The trailing DELETE only trims chunk_index >= the new chunk count
    # (2 here) — it must never be a blanket "delete everything for this
    # item_id" the way the old code's first step was.
    assert trim.url.params["item_id"] == "eq.item-1"
    assert trim.url.params["chunk_index"] == "gte.2"


@pytest.mark.asyncio
async def test_replace_chunks_with_no_chunks_still_trims_everything():
    requests: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        return httpx.Response(204)

    repo = _repo_with_transport(handler)
    try:
        await repo.replace_chunks("item-1", [])
    finally:
        await repo.aclose()

    # Nothing to upsert, but the trim still runs (chunk_index >= 0 is
    # every row) — same end state the old unconditional DELETE gave for
    # this case.
    assert [r.method for r in requests] == ["DELETE"]
    assert requests[0].url.params["chunk_index"] == "gte.0"


@pytest.mark.asyncio
async def test_replace_item_content_is_a_single_upsert_not_delete_then_insert():
    requests: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        return httpx.Response(201)

    repo = _repo_with_transport(handler)
    try:
        await repo.replace_item_content("item-1", raw_text="hello")
    finally:
        await repo.aclose()

    # A single atomic UPSERT — no DELETE at all, so there's no window
    # where a concurrent reprocessing run's own UPSERT could land
    # between this one's DELETE and INSERT.
    assert [r.method for r in requests] == ["POST"]
    upsert = requests[0]
    assert upsert.url.params["on_conflict"] == "item_id"
    assert upsert.headers["prefer"] == "resolution=merge-duplicates,return=minimal"
