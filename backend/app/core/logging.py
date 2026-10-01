"""Structured JSON logging. Never log content bodies, only identifiers/timings.
request_id/user_id travel via contextvars (per-asyncio-Task), so concurrent requests can't leak.
"""

import contextvars
import json
import logging
import sys
import time
import uuid
from collections.abc import Awaitable, Callable

from starlette.requests import Request
from starlette.responses import Response

request_id_var: contextvars.ContextVar[str | None] = contextvars.ContextVar(
    "request_id", default=None
)
user_id_var: contextvars.ContextVar[str | None] = contextvars.ContextVar("user_id", default=None)

# Default LogRecord attrs, to separate built-ins from caller-supplied `extra={...}` fields.
_STANDARD_RECORD_ATTRS = frozenset(vars(logging.LogRecord("", 0, "", 0, "", (), None))) | {
    "message",
    "asctime",
}


class _ContextFilter(logging.Filter):
    """Stamps request_id/user_id onto every record, even deep inside code with no request object."""

    def filter(self, record: logging.LogRecord) -> bool:
        record.request_id = request_id_var.get()
        record.user_id = user_id_var.get()
        return True


class _JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload: dict[str, object] = {
            "timestamp": self.formatTime(record, "%Y-%m-%dT%H:%M:%S%z"),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
        }
        for key, value in vars(record).items():
            if key in _STANDARD_RECORD_ATTRS or key.startswith("_"):
                continue
            if value is not None:
                payload[key] = value
        if record.exc_info:
            payload["error"] = self.formatException(record.exc_info)
        return json.dumps(payload, default=str)


# At DEBUG these log bodies/headers (incl. bearer tokens); pinned so root's level can't reach them.
_NOISY_THIRD_PARTY_LOGGERS = ("openai", "httpx", "httpcore")


def configure_logging(debug: bool = True) -> None:
    # Filter goes on the handler, not the logger: a root-logger filter never runs for child loggers.
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(_JsonFormatter())
    handler.addFilter(_ContextFilter())

    root = logging.getLogger()
    root.handlers = [handler]
    root.setLevel(logging.DEBUG if debug else logging.INFO)

    for name in _NOISY_THIRD_PARTY_LOGGERS:
        logging.getLogger(name).setLevel(logging.WARNING)


async def request_logging_middleware(
    request: Request, call_next: Callable[[Request], Awaitable[Response]]
) -> Response:
    """One log line per request; never body/query content. Echoes request_id as X-Request-Id."""
    request_id = str(uuid.uuid4())
    token = request_id_var.set(request_id)
    started = time.monotonic()
    logger = logging.getLogger("app.request")

    try:
        response = await call_next(request)
    except Exception:
        logger.exception(
            "request failed",
            extra={
                "method": request.method,
                "path": request.url.path,
                "processing_time_ms": round((time.monotonic() - started) * 1000, 1),
            },
        )
        request_id_var.reset(token)
        raise

    logger.info(
        "request completed",
        extra={
            "method": request.method,
            "path": request.url.path,
            "status_code": response.status_code,
            "processing_time_ms": round((time.monotonic() - started) * 1000, 1),
        },
    )
    response.headers["X-Request-Id"] = request_id
    request_id_var.reset(token)
    return response
