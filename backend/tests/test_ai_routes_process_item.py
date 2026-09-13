"""P1-05 (docs/requirements-audit-2026-09-13.md): `POST /ai/process-item`
used to create the `processing_jobs` row as `process_item()`'s own first
line — inside the `BackgroundTasks` callback, which FastAPI only runs
*after* "202 accepted" is already on the wire. A process death in that
gap left nothing behind: no job row for `job_recovery.py`'s startup
sweep to find, and a `create_job` failure itself never reached the
normal failed/status flow at all (it wasn't inside `process_item`'s own
try/except). These check the route now creates the job *before*
responding, and that a `create_job` failure surfaces as a normal failed
request instead of being silently swallowed by a background task no one
is watching.

`process_item` itself (the real pipeline) is monkeypatched out — this is
a route-level test of the accept/schedule contract, not the pipeline;
see test_processing_pipeline.py for that.
"""

import pytest
from fastapi.testclient import TestClient

from app.core.security import CurrentUser, get_current_user
from app.main import app

client = TestClient(app)


class _FakeRepo:
    def __init__(self, *, job_id: str | None = None, create_job_error: Exception | None = None):
        self.job_id = job_id
        self.create_job_error = create_job_error
        self.create_job_calls: list[tuple[str, str]] = []
        self.closed = False

    async def create_job(self, item_id: str, job_type: str) -> str:
        self.create_job_calls.append((item_id, job_type))
        if self.create_job_error is not None:
            raise self.create_job_error
        return self.job_id

    async def aclose(self) -> None:
        self.closed = True


@pytest.fixture(autouse=True)
def _authenticated():
    app.dependency_overrides[get_current_user] = lambda: CurrentUser(
        id="user-1", email="user@example.test", access_token="test-token"
    )
    yield
    app.dependency_overrides.pop(get_current_user, None)


def test_creates_the_job_before_returning_accepted(monkeypatch):
    fake_repo = _FakeRepo(job_id="job-1")
    monkeypatch.setattr("app.api.ai.routes.SupabaseRestRepository", lambda token: fake_repo)

    scheduled_job_ids = []

    async def fake_process_item(item_id, job_id, repo, get_provider, get_search_repo, **kwargs):
        scheduled_job_ids.append(job_id)

    monkeypatch.setattr("app.api.ai.routes.process_item", fake_process_item)

    response = client.post("/ai/process-item", json={"item_id": "item-1"})

    assert response.status_code == 202
    assert response.json() == {"status": "accepted", "item_id": "item-1"}
    # The job was created synchronously, as part of handling this
    # request — not deferred into the background task.
    assert fake_repo.create_job_calls == [("item-1", "chunk_and_embed")]
    # And the pipeline task was scheduled with that same, already-created
    # job id — not asked to create its own.
    assert scheduled_job_ids == ["job-1"]


def test_a_create_job_failure_surfaces_as_a_failed_request_not_silently_lost(monkeypatch):
    fake_repo = _FakeRepo(create_job_error=RuntimeError("db unreachable"))
    monkeypatch.setattr("app.api.ai.routes.SupabaseRestRepository", lambda token: fake_repo)

    process_item_called = False

    async def fake_process_item(*args, **kwargs):
        nonlocal process_item_called
        process_item_called = True

    monkeypatch.setattr("app.api.ai.routes.process_item", fake_process_item)

    response = client.post("/ai/process-item", json={"item_id": "item-1"})

    # A real error the client sees and can retry (the mobile app already
    # queues a `trigger_ai` retry on any such failure — see
    # SyncService._triggerAi) — not "202 accepted" for a job that was
    # never actually created anywhere.
    assert response.status_code == 503
    assert not process_item_called
    # The repository (and its HTTP connection) is released even on this
    # early failure, not just in process_item's own `finally`.
    assert fake_repo.closed is True
