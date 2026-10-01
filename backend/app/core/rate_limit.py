"""Per-user rate limiting for endpoints that call an AI provider.
Deliberately in-memory/single-process (no Redis): fine for one deployment, but each
instance would enforce its own window independently if ever scaled horizontally.
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
    Sliding, not fixed: can't be burst past by timing around a reset boundary.
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
        # Per-key size is bounded by `limit`, but distinct keys accumulate forever (no eviction).
        self._hits: dict[str, deque[float]] = defaultdict(deque)
        self._lock = asyncio.Lock()

    async def check(self, key: str) -> float | None:
        """None if allowed (and counted); otherwise seconds until a slot frees up."""
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
    """Drop-in for `Depends(get_current_user)` that also raises 429 past `bucket`'s limit."""

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
    """Factory, not a module-level singleton, so tests can use their own short-lived limiters."""
    return {
        "ai": SlidingWindowLimiter(limit=settings.rate_limit_ai_per_minute, window_seconds=60.0),
        "search": SlidingWindowLimiter(
            limit=settings.rate_limit_search_per_minute, window_seconds=60.0
        ),
    }


_limiters = build_limiters(get_settings())

require_ai_rate_limit = rate_limit_dependency("ai", _limiters["ai"])
require_search_rate_limit = rate_limit_dependency("search", _limiters["search"])
