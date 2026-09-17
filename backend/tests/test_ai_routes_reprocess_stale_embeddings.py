"""Route-level tests for `POST /ai/reprocess-stale-embeddings` (P3, docs/
requirements-audit-2026-09-13.md) — the Settings button that re-embeds
chunks left behind by an `AI_PROVIDER`/model switch. `reembed_stale_items`
itself (the real work) is monkeypatched out here — see
test_reembedding_service.py for that; this only checks the route's own
accept/count/error contract.
"""

import pytest
from fastapi.testclient import TestClient

from app.core.security import CurrentUser, get_current_user
from app.main import app
from app.services.ai_provider import AIProvider

client = TestClient(app)


class _FakeProvider(AIProvider):
    provider_name = "local"

    @property
    def embedding_model(self):
        return "nomic-embed-text"

    async def generate_text(self, prompt, *, system=None):
        raise NotImplementedError

    async def generate_embedding(self, text):
        raise NotImplementedError

    async def generate_embeddings(self, texts):
        raise NotImplementedError


class _FakeRepo:
    def __init__(self, *, stale_item_ids=None, find_stale_error=None):
        self.stale_item_ids = stale_item_ids or []
        self.find_stale_error = find_stale_error
        self.find_stale_calls = []
        self.closed = False

    async def find_stale_chunk_item_ids(self, current_provider, current_embedding_model):
        self.find_stale_calls.append((current_provider, current_embedding_model))
        if self.find_stale_error is not None:
            raise self.find_stale_error
        return self.stale_item_ids

    async def aclose(self):
        self.closed = True


@pytest.fixture(autouse=True)
def _authenticated():
    app.dependency_overrides[get_current_user] = lambda: CurrentUser(
        id="user-1", email="user@example.test", access_token="test-token"
    )
    yield
    app.dependency_overrides.pop(get_current_user, None)


def test_returns_202_with_the_stale_item_count_and_schedules_the_reembed(monkeypatch):
    fake_repo = _FakeRepo(stale_item_ids=["item-1", "item-2"])
    monkeypatch.setattr("app.api.ai.routes.SupabaseRestRepository", lambda token: fake_repo)
    monkeypatch.setattr("app.api.ai.routes.get_ai_provider", lambda settings: _FakeProvider())

    scheduled = []

    async def fake_reembed_stale_items(repo, provider):
        scheduled.append((repo, provider))
        return 2

    monkeypatch.setattr("app.api.ai.routes.reembed_stale_items", fake_reembed_stale_items)

    response = client.post("/ai/reprocess-stale-embeddings")

    assert response.status_code == 202
    assert response.json() == {"status": "accepted", "stale_item_count": 2}
    # Checked against the currently configured provider/model, not some
    # default — the whole point is comparing against *this* provider.
    assert fake_repo.find_stale_calls == [("local", "nomic-embed-text")]
    # The actual re-embedding really was scheduled (and, since TestClient
    # runs BackgroundTasks inline, already ran) against the same repo and
    # the currently configured provider.
    assert len(scheduled) == 1
    assert scheduled[0][0] is fake_repo
    assert isinstance(scheduled[0][1], _FakeProvider)
    assert fake_repo.closed is True


def test_nothing_stale_still_returns_202_with_a_zero_count(monkeypatch):
    fake_repo = _FakeRepo(stale_item_ids=[])
    monkeypatch.setattr("app.api.ai.routes.SupabaseRestRepository", lambda token: fake_repo)
    monkeypatch.setattr("app.api.ai.routes.get_ai_provider", lambda settings: _FakeProvider())
    monkeypatch.setattr(
        "app.api.ai.routes.reembed_stale_items", lambda repo, provider: _async_zero()
    )

    response = client.post("/ai/reprocess-stale-embeddings")

    assert response.status_code == 202
    assert response.json() == {"status": "accepted", "stale_item_count": 0}


async def _async_zero():
    return 0


def test_no_ai_provider_configured_surfaces_as_503_not_a_crash(monkeypatch):
    def _raise(settings):
        raise RuntimeError("AI_PROVIDER=openai but OPENAI_API_KEY is not set")

    monkeypatch.setattr("app.api.ai.routes.get_ai_provider", _raise)

    response = client.post("/ai/reprocess-stale-embeddings")

    assert response.status_code == 503
    assert "Re-embedding is unavailable" in response.json()["detail"]


def test_a_failure_checking_for_stale_chunks_surfaces_as_503_and_closes_the_repo(monkeypatch):
    fake_repo = _FakeRepo(find_stale_error=RuntimeError("db unreachable"))
    monkeypatch.setattr("app.api.ai.routes.SupabaseRestRepository", lambda token: fake_repo)
    monkeypatch.setattr("app.api.ai.routes.get_ai_provider", lambda settings: _FakeProvider())

    response = client.post("/ai/reprocess-stale-embeddings")

    assert response.status_code == 503
    assert fake_repo.closed is True
