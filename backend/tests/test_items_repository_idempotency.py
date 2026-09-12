"""HTTP-level regression tests for the idempotent-replace fix (Faz 10b,
madde 3 — see docs/roadmap.md). `replace_chunks`/`replace_item_content`
used to issue an independent DELETE followed by an independent INSERT;
the actual bug (two concurrent reprocessing runs doubling every chunk)
only shows up at the HTTP-request level, which the pipeline-level fakes
elsewhere (see test_processing_pipeline.py's `FakeRepo`) stand in for
and so can't see — these construct a real `SupabaseRestRepository` and
intercept its requests with `httpx.MockTransport` instead of hitting a
real database.

`replace_chunks` moved on again in Faz 12, madde 7 (denetim düzeltmesi
— see docs/roadmap.md): the UPSERT-then-DELETE pair fixed here still
left an older, slower job's delayed DELETE able to wipe a newer job's
already-written chunks. It's now a single atomic RPC call
(`replace_chunks_for_job`, infra/supabase/migrations/
0015_replace_chunks_atomic.sql) — the tests below check the HTTP shape
of that call; the actual per-item locking/staleness logic lives in SQL
and isn't exercised by these HTTP-level tests at all.
"""

import json

import httpx
import pytest

from app.repositories.items_repository import SupabaseRestRepository


def _repo_with_transport(handler) -> SupabaseRestRepository:
    repo = SupabaseRestRepository("test-token")
    # Pinned to a fixed, fake absolute URL rather than trusting whatever
    # `SUPABASE_URL` this repository's own `__init__` picked up from the
    # environment/`backend/.env` (a real bug, found live: this passed on
    # every machine that happens to have a real `backend/.env` checked
    # out locally — silently exercising a real Supabase host string —
    # and failed on any clean checkout, including CI, where
    # `settings.supabase_url` defaults to `""` and every request below
    # ends up as a bare relative path like `/rest/v1/...` — which
    # httpx's cookie-jar compatibility shim can't parse at all
    # (`ValueError: unknown url type`), regardless of the mock
    # transport ever being reached). Every assertion below reads
    # `.path`/`.params`, never the full URL, so pinning the host here
    # doesn't weaken anything real being checked.
    repo._base_url = "https://example.test"
    # Swap in a transport that never touches the network, after
    # construction, so the repository is built exactly the way
    # production code builds it (real headers).
    repo._client = httpx.AsyncClient(headers=repo._headers, transport=httpx.MockTransport(handler))
    return repo


@pytest.mark.asyncio
async def test_replace_chunks_calls_the_atomic_rpc_once_not_a_separate_upsert_and_delete():
    requests: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        return httpx.Response(200)

    repo = _repo_with_transport(handler)
    try:
        await repo.replace_chunks(
            "item-1",
            "job-1",
            [
                {"content": "a", "chunk_index": 0, "embedding": "[0]", "metadata": {}},
                {"content": "b", "chunk_index": 1, "embedding": "[0]", "metadata": {}},
            ],
        )
    finally:
        await repo.aclose()

    # One RPC call — not an UPSERT followed by a separate DELETE two
    # independent HTTP requests (and therefore a client crash/retry)
    # could interleave between (Faz 12, madde 7 — see docs/roadmap.md).
    assert [r.method for r in requests] == ["POST"]
    call = requests[0]
    assert call.url.path.endswith("/rest/v1/rpc/replace_chunks_for_job")
    body = json.loads(call.content)
    assert body["p_item_id"] == "item-1"
    assert body["p_job_id"] == "job-1"
    assert len(body["p_chunks"]) == 2


@pytest.mark.asyncio
async def test_replace_chunks_with_no_chunks_still_calls_the_rpc():
    requests: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        return httpx.Response(200)

    repo = _repo_with_transport(handler)
    try:
        await repo.replace_chunks("item-1", "job-1", [])
    finally:
        await repo.aclose()

    # No chunks to upsert, but the call still has to happen — the SQL
    # function is what decides to trim everything (chunk_index >= 0) in
    # that case, not this method.
    assert [r.method for r in requests] == ["POST"]
    assert json.loads(requests[0].content)["p_chunks"] == []


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
