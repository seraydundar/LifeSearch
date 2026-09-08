import io
import json
import logging
import sys

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.core.logging import _JsonFormatter, configure_logging, request_logging_middleware


@pytest.fixture
def logged_client(monkeypatch):
    """A TestClient wired through the real `configure_logging()` +
    `request_logging_middleware`, with stdout redirected into a buffer
    so a test can parse the actual JSON lines it would have written —
    this exercises the real handler+formatter+filter together instead of
    mocking any of them individually.

    Root logger state is restored afterward so this doesn't leak into
    other test files' logging.
    """
    root = logging.getLogger()
    original_handlers = list(root.handlers)
    original_filters = list(root.filters)
    original_level = root.level

    buffer = io.StringIO()
    monkeypatch.setattr(sys, "stdout", buffer)
    configure_logging(debug=True)

    app = FastAPI()
    app.middleware("http")(request_logging_middleware)

    @app.get("/ok")
    async def ok():
        return {"status": "ok"}

    @app.get("/boom")
    async def boom():
        raise RuntimeError("kaboom")

    yield TestClient(app, raise_server_exceptions=False), buffer

    root.handlers = original_handlers
    root.filters = original_filters
    root.level = original_level


def _log_lines(buffer: io.StringIO) -> list[dict]:
    return [json.loads(line) for line in buffer.getvalue().strip().splitlines() if line]


def test_response_carries_an_x_request_id_header(logged_client):
    client, _ = logged_client

    response = client.get("/ok")

    assert response.status_code == 200
    request_id = response.headers["x-request-id"]
    assert len(request_id) == 36  # a UUID4 string, e.g. 8-4-4-4-12 hex


def test_two_requests_get_different_request_ids(logged_client):
    client, _ = logged_client

    first = client.get("/ok").headers["x-request-id"]
    second = client.get("/ok").headers["x-request-id"]

    assert first != second


def test_a_successful_request_logs_one_json_line_with_the_expected_fields(logged_client):
    client, buffer = logged_client

    response = client.get("/ok")

    lines = [line for line in _log_lines(buffer) if line["logger"] == "app.request"]
    assert len(lines) == 1
    line = lines[0]
    assert line["message"] == "request completed"
    assert line["method"] == "GET"
    assert line["path"] == "/ok"
    assert line["status_code"] == 200
    assert line["processing_time_ms"] >= 0
    assert line["request_id"] == response.headers["x-request-id"]


def test_a_failed_request_still_logs_with_a_processing_time(logged_client):
    client, buffer = logged_client

    client.get("/boom")

    lines = [line for line in _log_lines(buffer) if line["logger"] == "app.request"]
    assert len(lines) == 1
    assert lines[0]["level"] == "ERROR"
    assert lines[0]["processing_time_ms"] >= 0
    # The exception itself lands in "error", never leaking into "message".
    assert "kaboom" not in lines[0]["message"]
    assert "kaboom" in lines[0]["error"]


def test_json_formatter_produces_valid_json_with_the_core_fields():
    record = logging.LogRecord(
        name="app.test",
        level=logging.INFO,
        pathname=__file__,
        lineno=1,
        msg="item processed",
        args=(),
        exc_info=None,
    )
    record.item_id = "item-1"
    record.processing_time_ms = 42.0

    payload = json.loads(_JsonFormatter().format(record))

    assert payload["message"] == "item processed"
    assert payload["level"] == "INFO"
    assert payload["logger"] == "app.test"
    assert payload["item_id"] == "item-1"
    assert payload["processing_time_ms"] == 42.0


def test_json_formatter_omits_fields_that_were_never_set():
    """`request_id`/`user_id` are `None` outside a request (or before
    auth resolves) — the JSON output shouldn't clutter every log line
    with `"request_id": null`.
    """
    record = logging.LogRecord(
        name="app.test",
        level=logging.INFO,
        pathname=__file__,
        lineno=1,
        msg="hello",
        args=(),
        exc_info=None,
    )
    record.request_id = None
    record.user_id = None

    payload = json.loads(_JsonFormatter().format(record))

    assert "request_id" not in payload
    assert "user_id" not in payload


def test_json_formatter_only_includes_fields_a_caller_actually_passed():
    """Regression guard for the "never log content" rule (requirements
    doc, section 53): the formatter doesn't invent fields — whatever
    isn't explicitly passed via `extra=` never appears, so keeping
    content out of logs stays entirely in each call site's hands.
    """
    record = logging.LogRecord(
        name="app.test",
        level=logging.INFO,
        pathname=__file__,
        lineno=1,
        msg="item processed",
        args=(),
        exc_info=None,
    )
    record.item_id = "item-1"

    payload = json.loads(_JsonFormatter().format(record))

    assert set(payload) == {"timestamp", "level", "logger", "message", "item_id"}
