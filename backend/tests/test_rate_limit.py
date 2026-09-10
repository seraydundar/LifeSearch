import pytest
from fastapi import Depends, FastAPI
from fastapi.testclient import TestClient

from app.core.rate_limit import SlidingWindowLimiter, rate_limit_dependency
from app.core.security import CurrentUser, get_current_user


class _FakeClock:
    """An injectable clock so window-expiry tests don't need a real
    `time.sleep` — matches the fake-repo/fake-provider pattern used
    throughout the rest of the backend's tests.
    """

    def __init__(self, start: float = 0.0) -> None:
        self.now = start

    def __call__(self) -> float:
        return self.now

    def advance(self, seconds: float) -> None:
        self.now += seconds


@pytest.fixture
def clock() -> _FakeClock:
    return _FakeClock()


@pytest.mark.asyncio
async def test_allows_calls_up_to_the_limit(clock):
    limiter = SlidingWindowLimiter(limit=3, window_seconds=60.0, now=clock)

    for _ in range(3):
        assert await limiter.check("user-1") is None


@pytest.mark.asyncio
async def test_denies_the_call_past_the_limit(clock):
    limiter = SlidingWindowLimiter(limit=2, window_seconds=60.0, now=clock)
    await limiter.check("user-1")
    await limiter.check("user-1")

    retry_after = await limiter.check("user-1")

    assert retry_after is not None
    assert retry_after > 0


@pytest.mark.asyncio
async def test_a_denied_call_is_not_counted_against_future_windows(clock):
    """Rejecting a call must not consume a slot — otherwise a client
    that retries after being rate-limited would never recover.
    """
    limiter = SlidingWindowLimiter(limit=1, window_seconds=60.0, now=clock)
    await limiter.check("user-1")
    await limiter.check("user-1")  # denied

    clock.advance(60.1)

    assert await limiter.check("user-1") is None


@pytest.mark.asyncio
async def test_different_keys_have_independent_budgets(clock):
    limiter = SlidingWindowLimiter(limit=1, window_seconds=60.0, now=clock)
    await limiter.check("user-1")

    assert await limiter.check("user-2") is None


@pytest.mark.asyncio
async def test_the_window_slides_rather_than_resetting_on_a_fixed_boundary(clock):
    """A fixed window would let a client burst 2x the limit around the
    reset point (limit at t=59, limit again at t=61). A sliding window
    shouldn't allow that.
    """
    limiter = SlidingWindowLimiter(limit=2, window_seconds=60.0, now=clock)
    await limiter.check("user-1")
    clock.advance(59.0)
    await limiter.check("user-1")

    clock.advance(2.0)  # t=61 — the first hit (t=0) is now outside the window

    assert await limiter.check("user-1") is None
    # ...but the second hit (t=59) is still inside it (t=61 - 60 = 1 < 59).
    assert await limiter.check("user-1") is not None


def _app_with_rate_limit(limiter: SlidingWindowLimiter) -> FastAPI:
    app = FastAPI()
    dependency = rate_limit_dependency("test-bucket", limiter)

    @app.get("/protected")
    async def protected(user: CurrentUser = Depends(dependency)):
        return {"user_id": user.id}

    app.dependency_overrides[get_current_user] = lambda: CurrentUser(
        id="user-1", email="user@example.com", access_token="token"
    )
    return app


def test_route_returns_200_under_the_limit(clock):
    limiter = SlidingWindowLimiter(limit=2, window_seconds=60.0, now=clock)
    client = TestClient(_app_with_rate_limit(limiter))

    response = client.get("/protected")

    assert response.status_code == 200
    assert response.json() == {"user_id": "user-1"}


def test_route_returns_429_with_retry_after_once_over_the_limit(clock):
    limiter = SlidingWindowLimiter(limit=1, window_seconds=60.0, now=clock)
    client = TestClient(_app_with_rate_limit(limiter))

    client.get("/protected")
    response = client.get("/protected")

    assert response.status_code == 429
    assert int(response.headers["retry-after"]) > 0
