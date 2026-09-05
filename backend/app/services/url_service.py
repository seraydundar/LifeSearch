"""Webpage content extraction for saved links (requirements doc, section
17): fetches the page, pulls out title/description/main text, and drops
navigation/ads/chrome — so what gets embedded is the article, not the
surrounding site.
"""

from typing import Any

import httpx
from bs4 import BeautifulSoup

_STRIP_TAGS = ["script", "style", "nav", "header", "footer", "aside", "form", "noscript", "iframe"]
_USER_AGENT = (
    "Mozilla/5.0 (compatible; LifeSearchBot/1.0; +https://github.com/seraydundar/LifeSearch)"
)


async def fetch_and_extract(url: str) -> dict[str, Any]:
    async with httpx.AsyncClient(timeout=20.0, follow_redirects=True) as client:
        response = await client.get(url, headers={"User-Agent": _USER_AGENT})
        response.raise_for_status()
    return extract_from_html(response.text)


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
