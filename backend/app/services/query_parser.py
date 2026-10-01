"""Turns a query like "geçen ay baktığım PDF'ler" into a type filter, a date
filter, and cleaned query text. Rule-based, not an LLM call: no API key
needed, and it runs before we know if a provider is even configured.
"""

import re
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

# Turkish keyword -> ItemType.dbValue.
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
    # Longest keyword first: dict order let "notlar" match inside "sesli
    # notlar" before the more specific phrase got a chance.
    for keyword in sorted(_TYPE_KEYWORDS, key=len, reverse=True):
        item_type = _TYPE_KEYWORDS[keyword]
        pattern = r"\b" + re.escape(keyword) + r"\b"
        if re.search(pattern, remaining, flags=re.IGNORECASE):
            found.add(item_type)
            remaining = re.sub(pattern, " ", remaining, flags=re.IGNORECASE)
    return remaining, sorted(found)


def _start_of_day(moment: datetime) -> datetime:
    return moment.replace(hour=0, minute=0, second=0, microsecond=0)


def _start_of_week(moment: datetime) -> datetime:
    start = _start_of_day(moment)
    return start - timedelta(days=start.weekday())


def _start_of_month(moment: datetime) -> datetime:
    return _start_of_day(moment).replace(day=1)


def _start_of_year(moment: datetime) -> datetime:
    return _start_of_day(moment).replace(month=1, day=1)


def _last_instant_before(period_start: datetime) -> datetime:
    """Inclusive upper bound for a "geçen X" range, one microsecond before the next period."""
    return period_start - timedelta(microseconds=1)


def _date_range_for_phrase(phrase: str, *, now: datetime) -> tuple[datetime, datetime | None]:
    """Calendar-correct ranges, not rolling windows. "bu X" (ongoing) has no
    upper bound; every "geçen X" (last X) is a closed period and needs one.
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
        # Day before the 1st of this month always falls in the previous month.
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


def parse_query(
    text: str, *, now: datetime | None = None, timezone_offset_minutes: int = 0
) -> ParsedQuery:
    """Shifts `now` by `timezone_offset_minutes` before resolving a date phrase
    and shifts results back, so date boundaries are local, not UTC.
    """
    now = now or datetime.now(UTC)
    offset = timedelta(minutes=timezone_offset_minutes)
    local_now = now + offset

    remaining, item_types = _extract_types(text)
    remaining, date_from, date_to = _extract_date(remaining, now=local_now)
    if date_from is not None:
        date_from -= offset
    if date_to is not None:
        date_to -= offset
    cleaned = re.sub(r"\s+", " ", remaining).strip()

    return ParsedQuery(
        # Fall back to the original text rather than embedding "" if the query was all filter words.
        cleaned_query=cleaned or text.strip(),
        item_types=item_types or None,
        date_from=date_from,
        date_to=date_to,
    )
