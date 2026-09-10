"""Per-user rate limiting for the endpoints that call an AI provider.

Every `/ai/process-item`, `/ai/ask` and `/search/` call ends up paying for
an OpenAI request (embedding, vision, Whisper or chat) — unlike a plain
CRUD call, that costs real money and takes real seconds. A client bug (a
sync loop that keeps retrying), a leaked bearer token, or someone simply
hammering "Ask AI" shouldn't be able to run up an unbounded bill through
this backend. This limits each *authenticated user* to N calls/minute per
bucket ("ai", "search") — plenty for a personal-archive app used by one
person, tight enough to cap the damage from any of the above.

**Deliberately in-memory, single-process** (rule 4, "gereksiz abstraction
oluşturma" — no Redis dependency for a limiter this simple). If this
service is ever scaled to multiple instances, each one enforces its own
window independently, so the effective limit becomes
`limit * instance_count` rather than a truly shared one. Fine for the
current single-deployment setup; a Redis-backed version would be the
next step before horizontal scaling.
"""

import asyncio
import logging
import time
from collections import defaultdict, deque
from collections.abc import Callable

from fastapi import Depends, HTTPException, status

from .config import Settings, get_settings
from .security import CurrentUser, get_current_user

logger = logging.getLogger("app.rate_limit")


class SlidingWindowLimiter:
    """Allows at most `limit` calls per `key` in any trailing `window_seconds`.

    A sliding (not fixed) window: it looks at the actual trailing window
    at call time rather than resetting on a clock boundary, so it can't be
    burst past by timing two windows' worth of requests around a fixed
    reset point.
    """

    def __init__(
        self,
        limit: int,
        window_seconds: float,
        *,
        now: Callable[[], float] = time.monotonic,
    ) -> None:
        self._limit = limit
        self._window = window_seconds
        self._now = now
        # Bounded by design: a key only ever holds up to `limit` timestamps
        # (a rejected call is never appended), so this can't grow without
        # bound per key. Distinct keys (distinct users) do accumulate
        # forever for the life of the process — acceptable for a personal
        # app's user count; would want an eviction pass for a large,
        # multi-tenant deployment.
        self._hits: dict[str, deque[float]] = defaultdict(deque)
        self._lock = asyncio.Lock()

    async def check(self, key: str) -> float | None:
        """Returns `None` if the call is allowed (and immediately counted
        against the window), otherwise the number of seconds until the
        oldest call in the window ages out and a slot frees up.
        """
        now = self._now()
        cutoff = now - self._window
        async with self._lock:
            hits = self._hits[key]
            while hits and hits[0] <= cutoff:
                hits.popleft()
            if len(hits) >= self._limit:
                return hits[0] + self._window - now
            hits.append(now)
            return None


def rate_limit_dependency(bucket: str, limiter: SlidingWindowLimiter):
    """Builds a FastAPI dependency that stands in for `Depends(get_current_user)`
    on a route: it resolves the user the same way (and the same instance
    of `get_current_user`, so FastAPI's per-request dependency caching
    means auth is still only verified once) and additionally raises 429
    once that user has exceeded `bucket`'s limit.
    """

    async def dependency(user: CurrentUser = Depends(get_current_user)) -> CurrentUser:
        retry_after = await limiter.check(f"{bucket}:{user.id}")
        if retry_after is not None:
            retry_after_s = max(1, round(retry_after))
            logger.warning(
                "rate limit exceeded",
                extra={"bucket": bucket, "retry_after_s": retry_after_s},
            )
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail="Too many requests — slow down and try again shortly.",
                headers={"Retry-After": str(retry_after_s)},
            )
        return user

    return dependency


def build_limiters(settings: Settings) -> dict[str, SlidingWindowLimiter]:
    """Factory (rather than module-level singletons) so tests can build
    their own short-lived limiters with small limits/windows instead of
    sharing process-wide state across test cases.
    """
    return {
        "ai": SlidingWindowLimiter(limit=settings.rate_limit_ai_per_minute, window_seconds=60.0),
        "search": SlidingWindowLimiter(
            limit=settings.rate_limit_search_per_minute, window_seconds=60.0
        ),
    }


_limiters = build_limiters(get_settings())

# Ready-made dependencies — routes use these in place of
# `Depends(get_current_user)` on the specific endpoints that call an AI
# provider.
require_ai_rate_limit = rate_limit_dependency("ai", _limiters["ai"])
require_search_rate_limit = rate_limit_dependency("search", _limiters["search"])
