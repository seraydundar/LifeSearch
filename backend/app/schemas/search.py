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


class RelatedResponse(BaseModel):
    item_id: str
    results: list[SearchResult]
