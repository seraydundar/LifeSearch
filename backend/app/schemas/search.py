from datetime import datetime

from pydantic import BaseModel, Field


class SearchRequest(BaseModel):
    query: str
    limit: int = 10
    # Metadata filters (requirements doc, section 21) — the mobile app
    # turns "Today"/"Last week"/"Last month" presets into an actual
    # date_from before sending the request.
    item_types: list[str] | None = None
    date_from: datetime | None = None
    date_to: datetime | None = None
    # P2-02 (docs/requirements-audit-2026-09-13.md): the client's own UTC
    # offset in minutes (Dart's `DateTime.now().timeZoneOffset.inMinutes`
    # — positive when local time is ahead of UTC, e.g. +180 for Turkey),
    # so `query_parser.parse_query` can resolve a free-text date phrase
    # ("bugün", "dün") against the user's actual local calendar day
    # instead of a UTC one. Bounded to the real range of UTC offsets
    # (-12:00..+14:00) as basic input validation at this request boundary.
    timezone_offset_minutes: int = Field(default=0, ge=-720, le=840)
    # True only once the device's own private reveal (biometric/PIN) is
    # unlocked — see `privateItemsRevealedProvider` — so private items are
    # excluded in SQL by default (P1-02, docs/requirements-audit-2026-09-13.md)
    # instead of merely being hidden client-side after already being sent.
    include_private: bool = False


class SearchResult(BaseModel):
    item_id: str
    item_type: str
    item_title: str | None
    snippet: str
    similarity: float


class SearchResponse(BaseModel):
    query: str
    results: list[SearchResult]


class RelatedRequest(BaseModel):
    item_id: str
    limit: int = 6
    include_private: bool = False


class RelatedResponse(BaseModel):
    item_id: str
    results: list[SearchResult]
