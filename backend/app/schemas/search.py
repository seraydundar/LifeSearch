from datetime import datetime

from pydantic import BaseModel, Field


class SearchRequest(BaseModel):
    query: str
    limit: int = 10
    # The mobile app turns "Today"/"Last week"/"Last month" presets into an actual date_from.
    item_types: list[str] | None = None
    date_from: datetime | None = None
    date_to: datetime | None = None
    # Client's UTC offset in minutes, so date phrases resolve against the user's local day, not UTC.
    timezone_offset_minutes: int = Field(default=0, ge=-720, le=840)
    # True only once the device's private reveal is unlocked; excluded in SQL by default otherwise.
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
