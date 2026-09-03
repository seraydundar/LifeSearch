from pydantic import BaseModel


class SearchRequest(BaseModel):
    query: str
    limit: int = 10


class SearchResult(BaseModel):
    item_id: str
    item_type: str
    item_title: str | None
    snippet: str
    similarity: float


class SearchResponse(BaseModel):
    query: str
    results: list[SearchResult]
