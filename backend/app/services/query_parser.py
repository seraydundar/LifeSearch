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
    date_to: datetime | None


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


def _start_of_week(moment: datetime) -> datetime:
    start = _start_of_day(moment)
    return start - timedelta(days=start.weekday())  # Monday


def _start_of_month(moment: datetime) -> datetime:
    return _start_of_day(moment).replace(day=1)


def _start_of_year(moment: datetime) -> datetime:
    return _start_of_day(moment).replace(month=1, day=1)


def _last_instant_before(period_start: datetime) -> datetime:
    """The latest representable moment strictly before `period_start` —
    closes off a "geçen X" (last X) range at an inclusive upper bound
    (the hybrid RPC's `created_at <= filter_before` treats both bounds
    as inclusive, see infra/supabase/migrations/0006_hybrid_and_related.sql)
    without it leaking one microsecond into the period that follows.
    """
    return period_start - timedelta(microseconds=1)


def _date_range_for_phrase(phrase: str, *, now: datetime) -> tuple[datetime, datetime | None]:
    """Calendar-correct ranges, not rolling windows — "geçen ay" (last
    month) used to be `today - 30 days`, which is wrong for any month
    that isn't exactly 30 days long (11 of the 12 are), and "bugün"/"dün"
    had no upper bound at all, so "dün" (yesterday) actually matched
    everything from yesterday onward, today included (see docs/roadmap.md,
    Faz 10c, madde 2). "bu X" (this X, still ongoing) legitimately has no
    upper bound — nothing can be dated in the future — but every "geçen X"
    (last X) is a *closed* period and needs one.
    """
    today = _start_of_day(now)
    this_week = _start_of_week(today)
    this_month = _start_of_month(today)
    this_year = _start_of_year(today)

    if phrase == "bugün":
        return today, None
    if phrase == "dün":
        return today - timedelta(days=1), _last_instant_before(today)
    if phrase == "bu hafta":
        return this_week, None
    if phrase == "geçen hafta":
        return this_week - timedelta(days=7), _last_instant_before(this_week)
    if phrase == "bu ay":
        return this_month, None
    if phrase == "geçen ay":
        # The day before the 1st of this month always falls in the
        # previous month, whatever that month's actual length was.
        last_month = _start_of_month(this_month - timedelta(days=1))
        return last_month, _last_instant_before(this_month)
    if phrase == "bu yıl":
        return this_year, None
    if phrase == "geçen yıl":
        return this_year.replace(year=this_year.year - 1), _last_instant_before(this_year)
    raise AssertionError(f"unhandled date phrase: {phrase!r}")  # unreachable: see _DATE_PHRASES


def _extract_date(text: str, *, now: datetime) -> tuple[str, datetime | None, datetime | None]:
    for phrase in _DATE_PHRASES:
        pattern = r"\b" + re.escape(phrase) + r"\b"
        if re.search(pattern, text, flags=re.IGNORECASE):
            remaining = re.sub(pattern, " ", text, flags=re.IGNORECASE)
            date_from, date_to = _date_range_for_phrase(phrase, now=now)
            return remaining, date_from, date_to
    return text, None, None


def parse_query(text: str, *, now: datetime | None = None) -> ParsedQuery:
    now = now or datetime.now(UTC)

    remaining, item_types = _extract_types(text)
    remaining, date_from, date_to = _extract_date(remaining, now=now)
    cleaned = re.sub(r"\s+", " ", remaining).strip()

    return ParsedQuery(
        # Never hand back an empty query just because it was all filter
        # words ("geçen ay pdfler") — fall back to searching the original
        # text rather than embedding "".
        cleaned_query=cleaned or text.strip(),
        item_types=item_types or None,
        date_from=date_from,
        date_to=date_to,
    )
