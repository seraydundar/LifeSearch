"""Fetches a saved webpage and extracts title/description/main text.

SSRF-sensitive: fetches a user-supplied URL with the backend's own network
access. `_ensure_safe_to_fetch()` rejects non-http(s) schemes and any host
resolving to a non-public address, re-checked on every redirect hop.
`_fetch_safely()` connects to that pre-validated IP directly (Host/SNI kept
as the real hostname) rather than letting httpx re-resolve, closing a
DNS-rebinding race between the check and the actual connection.
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

# Generous — a real article page is a few hundred KB at most.
_MAX_RESPONSE_BYTES = 5 * 1024 * 1024
_MAX_REDIRECTS = 5


class UnsafeUrlError(Exception):
    """Safe to surface as-is to the user — message never includes response body content."""


async def fetch_and_extract(url: str) -> dict[str, Any]:
    html = await _fetch_safely(url)
    return extract_from_html(html)


async def _fetch_safely(url: str) -> str:
    """Follows redirects manually so every hop gets the same safety check."""
    current_url = url
    async with httpx.AsyncClient(timeout=20.0, follow_redirects=False) as client:
        for _ in range(_MAX_REDIRECTS + 1):
            pinned_ip = await _ensure_safe_to_fetch(current_url)
            parsed = urlparse(current_url)
            host_header = parsed.hostname if not parsed.port else f"{parsed.hostname}:{parsed.port}"
            # Connect to the pre-validated IP (DNS-rebinding guard); Host/SNI stay real.
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
    """Split out so tests can fake DNS resolution without real network access."""
    try:
        infos = await asyncio.get_running_loop().getaddrinfo(hostname, None)
    except OSError as error:
        raise UnsafeUrlError(f"Could not resolve host: {hostname!r}") from error
    return [info[4][0] for info in infos]


async def _ensure_safe_to_fetch(url: str) -> str:
    """Returns the IP to connect to: the first resolved address, but only
    once every address for this host has passed the public-address check.
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
        # is_global excludes private/loopback/link-local (incl. 169.254.169.254
        # cloud metadata)/multicast/reserved ranges in one check.
        if not ip.is_global:
            raise UnsafeUrlError(
                f"{parsed.hostname!r} resolves to a non-public address ({ip}) — refusing."
            )
    return addresses[0]


def extract_from_html(html: str) -> dict[str, Any]:
    """Split out from the fetch so it's testable with a plain HTML string."""
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
