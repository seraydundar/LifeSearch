from pydantic import BaseModel

from .search import SearchResult


class ProcessItemRequest(BaseModel):
    item_id: str


class ProcessItemResponse(BaseModel):
    status: str
    item_id: str


class AskRequest(BaseModel):
    question: str
    limit: int = 8


class AskResponse(BaseModel):
    question: str
    answer: str
    sources: list[SearchResult]
