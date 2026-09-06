"""Natural-language filter extraction (requirements doc, section 22) —
turns a query like "geçen ay baktığım PDF'ler" into a type filter, a date
filter, and a cleaned-up query text to actually embed/search on.

Deliberately rule-based rather than an LLM call: no API key needed, and
it runs before we know whether a provider is even configured. It only
ever *extends* what the client already sent — `/search/` treats any
filter already given in the request as authoritative and just fills in
the gaps from what this recognizes (see `api/search/routes.py`).
"""

import re
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

# Turkish keyword -> ItemType.dbValue (see mobile's ItemType / items.type
# check constraint). Longest-first so e.g. "ekran görüntüsü" is tried
# before a bare "görüntü" would otherwise partially match.
_TYPE_KEYWORDS: dict[str, str] = {
    "ekran görüntüleri": "screenshot",
    "ekran görüntüsü": "screenshot",
    "screenshotlar": "screenshot",
    "screenshot": "screenshot",
    "fotoğraflarım": "image",
    "fotoğraflar": "image",
    "fotoğraf": "image",
    "resimlerim": "image",
    "resimler": "image",
    "resim": "image",
    "pdf'lerim": "pdf",
    "pdf'ler": "pdf",
    "pdfler": "pdf",
    "pdf": "pdf",
    "notlarım": "note",
    "notlar": "note",
    "notum": "note",
    "not": "note",
    "bağlantılar": "url",
    "bağlantı": "url",
    "linklerim": "url",
    "linkler": "url",
    "link": "url",
    "ses kayıtlarım": "audio",
    "ses kayıtları": "audio",
    "ses kaydı": "audio",
    "sesli notlar": "audio",
    "sesli not": "audio",
    "belgelerim": "document",
    "belgeler": "document",
    "belge": "document",
    "dokümanlar": "document",
    "doküman": "document",
}

# Longest phrase first so "geçen hafta" is tried before a lone "hafta".
_DATE_PHRASES = sorted(
    ["bugün", "dün", "geçen hafta", "bu hafta", "geçen ay", "bu ay", "geçen yıl", "bu yıl"],
    key=len,
    reverse=True,
)


@dataclass
class ParsedQuery:
    cleaned_query: str
    item_types: list[str] | None
    date_from: datetime | None


def _strip(text: str, phrase: str) -> str:
    return re.sub(re.escape(phrase), " ", text, flags=re.IGNORECASE)


def _extract_types(text: str) -> tuple[str, list[str]]:
    remaining = text
    found: set[str] = set()
    for keyword, item_type in _TYPE_KEYWORDS.items():
        pattern = r"\b" + re.escape(keyword) + r"\b"
        if re.search(pattern, remaining, flags=re.IGNORECASE):
            found.add(item_type)
            remaining = re.sub(pattern, " ", remaining, flags=re.IGNORECASE)
    return remaining, sorted(found)


def _start_of_day(moment: datetime) -> datetime:
    return moment.replace(hour=0, minute=0, second=0, microsecond=0)


def _date_from_phrase(phrase: str, *, now: datetime) -> datetime:
    today = _start_of_day(now)
    return {
        "bugün": today,
        "dün": today - timedelta(days=1),
        "bu hafta": today - timedelta(days=today.weekday()),
        "geçen hafta": today - timedelta(days=7),
        "bu ay": today.replace(day=1),
        "geçen ay": today - timedelta(days=30),
        "bu yıl": today.replace(month=1, day=1),
        "geçen yıl": today - timedelta(days=365),
    }[phrase]


def _extract_date(text: str, *, now: datetime) -> tuple[str, datetime | None]:
    for phrase in _DATE_PHRASES:
        pattern = r"\b" + re.escape(phrase) + r"\b"
        if re.search(pattern, text, flags=re.IGNORECASE):
            remaining = re.sub(pattern, " ", text, flags=re.IGNORECASE)
            return remaining, _date_from_phrase(phrase, now=now)
    return text, None


def parse_query(text: str, *, now: datetime | None = None) -> ParsedQuery:
    now = now or datetime.now(UTC)

    remaining, item_types = _extract_types(text)
    remaining, date_from = _extract_date(remaining, now=now)
    cleaned = re.sub(r"\s+", " ", remaining).strip()

    return ParsedQuery(
        # Never hand back an empty query just because it was all filter
        # words ("geçen ay pdfler") — fall back to searching the original
        # text rather than embedding "".
        cleaned_query=cleaned or text.strip(),
        item_types=item_types or None,
        date_from=date_from,
    )
