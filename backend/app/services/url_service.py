"""Webpage content extraction for saved links (requirements doc, section
17): fetches the page, pulls out title/description/main text, and drops
navigation/ads/chrome — so what gets embedded is the article, not the
surrounding site.

Security (Faz 10b, madde 4 — see docs/roadmap.md): this fetches a
user-supplied URL with the *backend's own* network access — the
textbook SSRF setup (a saved link could point at an internal admin
panel, a database, or a cloud provider's metadata endpoint, which on
most clouds hands back real credentials to whatever can reach it).
`_ensure_safe_to_fetch()` rejects a URL (or any redirect hop — redirects
are followed manually, one at a time, specifically so each one gets
checked before it's ever requested) whose scheme isn't http(s) or whose
host resolves to anything other than a public, globally-routable
address. `_fetch_safely()` additionally caps the response body size and
rejects a non-HTML content-type, so a saved link can't be used to make
this backend download something unbounded or something there's nothing
useful to extract from anyway.

**DNS rebinding (P1-06, docs/requirements-audit-2026-09-13.md)**:
`_ensure_safe_to_fetch()` used to resolve the hostname once and then let
httpx resolve it again, independently, to actually connect — a
DNS-rebinding attacker who changed the answer between those two lookups
(their DNS record pointing at a public IP the first time, an internal
one the second) could slip an unsafe address past the check entirely.
`_fetch_safely()` now connects to the exact IP `_ensure_safe_to_fetch()`
already validated (`request.url`'s host becomes that IP), rather than
trusting a second, independent resolution — there's no longer a second
lookup for an attacker to race. The `Host` header and TLS SNI are set
explicitly to the real hostname (`extensions={"sni_hostname": ...}`) so
the request still looks — and, for TLS, still verifies — like a normal
request to that hostname; only the actual connection target is pinned.
"""

import asyncio
import ipaddress
from typing import Any
from urllib.parse import urlparse

import httpx
from bs4 import BeautifulSoup

_STRIP_TAGS = ["script", "style", "nav", "header", "footer", "aside", "form", "noscript", "iframe"]
_USER_AGENT = (
    "Mozilla/5.0 (compatible; LifeSearchBot/1.0; +https://github.com/seraydundar/LifeSearch)"
)

# An article page is a few hundred KB at most, even a heavy one — this is
# already generous, not a tight limit picked to just barely fit real pages.
_MAX_RESPONSE_BYTES = 5 * 1024 * 1024
_MAX_REDIRECTS = 5


class UnsafeUrlError(Exception):
    """The URL — or a redirect it led to — isn't safe for this backend to
    fetch. Reaches `process_item()`'s existing broad `except Exception`
    (see processing_pipeline.py), which marks the item/job failed with
    `str(error)` as the message — safe to surface as-is, since every
    message here only ever describes the URL/host/limit, never anything
    from the response body.
    """


async def fetch_and_extract(url: str) -> dict[str, Any]:
    html = await _fetch_safely(url)
    return extract_from_html(html)


async def _fetch_safely(url: str) -> str:
    """Follows redirects itself (`follow_redirects=False` below) rather
    than letting httpx do it — the whole point of checking each URL is
    defeated if a *redirect target* never gets the same check.
    """
    current_url = url
    async with httpx.AsyncClient(timeout=20.0, follow_redirects=False) as client:
        for _ in range(_MAX_REDIRECTS + 1):
            pinned_ip = await _ensure_safe_to_fetch(current_url)
            parsed = urlparse(current_url)
            host_header = parsed.hostname if not parsed.port else f"{parsed.hostname}:{parsed.port}"
            # Connect to `pinned_ip`, not `current_url`'s own hostname —
            # see the module docstring's "DNS rebinding" note. `Host` and
            # SNI stay the real hostname so the request (and, for https,
            # certificate verification) still matches it.
            pinned_url = httpx.URL(current_url).copy_with(host=pinned_ip)
            request = client.build_request(
                "GET",
                pinned_url,
                headers={"User-Agent": _USER_AGENT, "Host": host_header},
                extensions={"sni_hostname": parsed.hostname},
            )
            response = await client.send(request, stream=True)
            try:
                if response.is_redirect:
                    location = response.headers.get("location")
                    if not location:
                        raise UnsafeUrlError("Redirect response had no Location header.")
                    current_url = str(httpx.URL(current_url).join(location))
                    continue

                response.raise_for_status()
                content_type = response.headers.get("content-type", "").split(";")[0].strip()
                if content_type and "html" not in content_type:
                    raise UnsafeUrlError(
                        f"Saved link isn't an HTML page (content-type: {content_type!r})."
                    )

                body = b""
                async for chunk in response.aiter_bytes():
                    body += chunk
                    if len(body) > _MAX_RESPONSE_BYTES:
                        raise UnsafeUrlError(
                            f"Saved link's response exceeded {_MAX_RESPONSE_BYTES} bytes."
                        )
                return body.decode(response.charset_encoding or "utf-8", errors="replace")
            finally:
                await response.aclose()

    raise UnsafeUrlError(f"Too many redirects (> {_MAX_REDIRECTS}) while fetching a saved link.")


async def _resolve_addresses(hostname: str) -> list[str]:
    """Split out from `_ensure_safe_to_fetch` purely so tests can
    substitute canned results for a *symbolic* hostname instead of
    needing real DNS/network access to exercise it (see
    test_url_service_ssrf.py) — a literal IP (which is what every actual
    SSRF target here is) never reaches real resolution either way, real
    or faked, since parsing a literal address needs no network call.
    """
    try:
        infos = await asyncio.get_running_loop().getaddrinfo(hostname, None)
    except OSError as error:
        raise UnsafeUrlError(f"Could not resolve host: {hostname!r}") from error
    return [info[4][0] for info in infos]


async def _ensure_safe_to_fetch(url: str) -> str:
    """Returns the resolved address `_fetch_safely()` should actually
    connect to (see its "DNS rebinding" note) — the *first* validated
    one, once every resolved address for this host has passed the
    public-address check below. A host resolving to a mix of public and
    non-public addresses is still refused entirely: picking only the
    first-validated address to connect to isn't a safety compromise
    (that's all any single connection ever uses anyway), but a host
    that resolves to a private address *at all* is treated as unsafe
    outright, same as before this returned anything.
    """
    parsed = urlparse(url)
    if parsed.scheme not in ("http", "https"):
        raise UnsafeUrlError(f"Unsupported URL scheme for a saved link: {parsed.scheme!r}")
    if not parsed.hostname:
        raise UnsafeUrlError("Saved link has no host.")

    addresses = await _resolve_addresses(parsed.hostname)
    if not addresses:
        raise UnsafeUrlError(f"Could not resolve host: {parsed.hostname!r}")
    for address in addresses:
        ip = ipaddress.ip_address(address)
        # is_global is the one check that already excludes private
        # (RFC 1918), loopback, link-local (including the cloud metadata
        # address 169.254.169.254), multicast, reserved and unspecified
        # ranges in one go — every one of those is exactly what an SSRF
        # attempt targets.
        if not ip.is_global:
            raise UnsafeUrlError(
                f"{parsed.hostname!r} resolves to a non-public address ({ip}) — refusing."
            )
    return addresses[0]


def extract_from_html(html: str) -> dict[str, Any]:
    """Pure parsing step, split out from the network fetch above so it's
    testable with a plain HTML string instead of a mocked HTTP client.
    """
    soup = BeautifulSoup(html, "html.parser")

    title = soup.title.get_text(strip=True) if soup.title else ""
    description_tag = soup.find("meta", attrs={"name": "description"})
    description = (
        description_tag.get("content", "").strip()
        if description_tag and description_tag.get("content")
        else ""
    )

    for tag in soup.find_all(_STRIP_TAGS):
        tag.decompose()

    main = soup.find("article") or soup.find("main") or soup.body
    text = main.get_text(separator="\n", strip=True) if main else ""

    return {"title": title, "description": description, "text": text}
