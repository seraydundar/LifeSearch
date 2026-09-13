from datetime import datetime

from pydantic import BaseModel


class SearchRequest(BaseModel):
    query: str
    limit: int = 10
    # Metadata filters (requirements doc, section 21) — the mobile app
    # turns "Today"/"Last week"/"Last month" presets into an actual
    # date_from before sending the request.
    item_types: list[str] | None = None
    date_from: datetime | None = None
    date_to: datetime | None = None
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
