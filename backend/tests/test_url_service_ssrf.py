"""Faz 10b, madde 4 (see docs/roadmap.md): `fetch_and_extract()` fetches
a user-supplied URL with this backend's own network access — these
guard the SSRF surface that opens. No real network calls happen here:
a literal IP needs no DNS lookup to parse, and `_resolve_addresses` is
faked wherever a symbolic hostname ("public.example.com") is used, so
these never depend on real DNS or network access.
"""

import httpx
import pytest

import app.services.url_service as url_service
from app.services.url_service import UnsafeUrlError, _ensure_safe_to_fetch, fetch_and_extract

_real_resolve_addresses = url_service._resolve_addresses


def _fake_public_dns(monkeypatch: pytest.MonkeyPatch) -> None:
    """Makes `public.example.com` resolve to a public IP without a real
    DNS query; every other hostname (in particular a redirect target
    that's already a literal IP, like 169.254.169.254) still goes
    through the real resolver — which needs no network access for a
    literal IP either, so this stays fully offline.
    """

    async def fake_resolve(hostname: str) -> list[str]:
        if hostname == "public.example.com":
            return ["93.184.215.14"]
        return await _real_resolve_addresses(hostname)

    monkeypatch.setattr(url_service, "_resolve_addresses", fake_resolve)


_RealAsyncClient = httpx.AsyncClient


def _mock_client(monkeypatch: pytest.MonkeyPatch, handler) -> None:
    monkeypatch.setattr(
        "httpx.AsyncClient",
        lambda *a, **kw: _RealAsyncClient(*a, transport=httpx.MockTransport(handler), **kw),
    )


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "url",
    [
        "http://127.0.0.1/",
        "http://localhost/",
        "http://169.254.169.254/latest/meta-data/",  # cloud metadata endpoint
        "http://192.168.1.1/",
        "http://10.0.0.5/",
        "http://[::1]/",
    ],
)
async def test_rejects_non_public_addresses(url: str):
    with pytest.raises(UnsafeUrlError):
        await _ensure_safe_to_fetch(url)


@pytest.mark.asyncio
async def test_accepts_a_public_address():
    await _ensure_safe_to_fetch("http://8.8.8.8/")  # must not raise


@pytest.mark.asyncio
@pytest.mark.parametrize("url", ["file:///etc/passwd", "gopher://127.0.0.1/", "ftp://example.com/"])
async def test_rejects_non_http_schemes(url: str):
    with pytest.raises(UnsafeUrlError):
        await _ensure_safe_to_fetch(url)


@pytest.mark.asyncio
async def test_rejects_a_redirect_to_a_non_public_address(monkeypatch: pytest.MonkeyPatch):
    """The whole point of checking redirects one hop at a time — a
    public-looking URL that 302s to an internal address must be caught
    just as surely as requesting the internal address directly.
    """
    _fake_public_dns(monkeypatch)

    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.host == "public.example.com":
            return httpx.Response(302, headers={"location": "http://169.254.169.254/secret"})
        raise AssertionError(f"should never actually request {request.url}")

    _mock_client(monkeypatch, handler)

    with pytest.raises(UnsafeUrlError):
        await fetch_and_extract("http://public.example.com/")


@pytest.mark.asyncio
async def test_rejects_a_response_over_the_size_limit(monkeypatch: pytest.MonkeyPatch):
    _fake_public_dns(monkeypatch)
    monkeypatch.setattr(url_service, "_MAX_RESPONSE_BYTES", 10)

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, headers={"content-type": "text/html"}, content=b"x" * 1000)

    _mock_client(monkeypatch, handler)

    with pytest.raises(UnsafeUrlError):
        await fetch_and_extract("http://public.example.com/")


@pytest.mark.asyncio
async def test_rejects_a_non_html_response(monkeypatch: pytest.MonkeyPatch):
    _fake_public_dns(monkeypatch)

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, headers={"content-type": "application/pdf"}, content=b"%PDF-1.4")

    _mock_client(monkeypatch, handler)

    with pytest.raises(UnsafeUrlError):
        await fetch_and_extract("http://public.example.com/")


@pytest.mark.asyncio
async def test_accepts_an_html_response_and_extracts_it(monkeypatch: pytest.MonkeyPatch):
    _fake_public_dns(monkeypatch)

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            headers={"content-type": "text/html; charset=utf-8"},
            content=b"<html><head><title>Hi</title></head><body><p>hello</p></body></html>",
        )

    _mock_client(monkeypatch, handler)

    result = await fetch_and_extract("http://public.example.com/")

    assert result["title"] == "Hi"
    assert "hello" in result["text"]


@pytest.mark.asyncio
async def test_gives_up_after_too_many_redirects(monkeypatch: pytest.MonkeyPatch):
    _fake_public_dns(monkeypatch)

    def handler(request: httpx.Request) -> httpx.Response:
        # Always redirects to itself — a loop, same shape as a
        # misconfigured (or deliberately hostile) server.
        return httpx.Response(302, headers={"location": "http://public.example.com/"})

    _mock_client(monkeypatch, handler)

    with pytest.raises(UnsafeUrlError):
        await fetch_and_extract("http://public.example.com/")
