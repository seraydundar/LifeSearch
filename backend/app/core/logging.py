"""Structured logging (requirements doc, section 53).

Every log line is one JSON object on stdout with a timestamp, level,
logger name, and message, plus whatever identifiers actually apply:
`request_id` (every request, via `request_logging_middleware`),
`user_id` (once auth resolves it, via `core.security.get_current_user`),
and — passed explicitly at each call site — `job_id`, `item_id`,
`processing_time_ms`. Rule: never log personal document/content bodies,
only identifiers and timings.

`request_id`/`user_id` travel through `contextvars` rather than being
threaded through every function signature — each request runs in its own
asyncio Task, which gets its own copy of the context (PEP 567), so one
request's values never leak into another's concurrently-running logs.
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

# Every attribute a stdlib LogRecord carries by default — used to tell
# "the message and its built-ins" apart from whatever a caller passed via
# `extra={...}`, which is what actually gets merged into the JSON output.
_STANDARD_RECORD_ATTRS = frozenset(vars(logging.LogRecord("", 0, "", 0, "", (), None))) | {
    "message",
    "asctime",
}


class _ContextFilter(logging.Filter):
    """Stamps the current request's request_id/user_id onto every record
    emitted while handling it — including from deep inside the AI
    pipeline, which never sees a request object at all.
    """

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


# Nothing in this app's own code calls `logger.debug(...)` — `debug`
# only ever existed to make root-logger output more verbose in
# development. Setting the *root* logger to DEBUG did that, but Python's
# logging hierarchy means every third-party logger that never sets its
# own level (which is the normal, well-behaved way to write a library)
# inherits that same DEBUG threshold — including these, whose DEBUG
# output includes exactly what requirements doc, section 53 says never
# to log: `openai`'s SDK logs full request/response bodies (prompts,
# embedding input) at DEBUG, and `httpx`/`httpcore` (which every
# repository here uses directly for Supabase, not just the OpenAI
# client) can log request headers at DEBUG — including the
# `Authorization` bearer token, i.e. the signed-in user's own session,
# or `service_role`'s if that repository happens to be the sweep in
# job_recovery.py. Pinning each of these to its own level, regardless of
# `debug`, stops root's level from ever reaching them — a logger's
# *own* level always wins over whatever level an ancestor has.
_NOISY_THIRD_PARTY_LOGGERS = ("openai", "httpx", "httpcore")


def configure_logging(debug: bool = True) -> None:
    # On the handler, not the logger: `Logger.filter()` only checks the
    # *originating* logger's own filters (e.g. `getLogger("app.request")`,
    # not root), so a filter added to root would silently never run for
    # any child logger. A handler's filter, by contrast, runs for every
    # record that reaches it regardless of which logger it came from —
    # which is what actually stamps request_id/user_id onto everything.
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
    """One log line per request — method/path/status/processing_time_ms,
    never the body or query string content (requirements doc, section
    53). Also echoes `request_id` back as `X-Request-Id` so a report from
    the mobile app can be matched to server-side logs.
    """
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
