from pydantic import BaseModel

from .search import SearchResult


class ProcessItemRequest(BaseModel):
    item_id: str


class ProcessItemResponse(BaseModel):
    status: str
    item_id: str


class ChatTurn(BaseModel):
    """role is "user" or "assistant", mirroring the mobile app's ChatRole."""

    role: str
    text: str


class AskRequest(BaseModel):
    question: str
    limit: int = 8
    # Oldest first; does not include `question` itself.
    history: list[ChatTurn] = []


class AskResponse(BaseModel):
    question: str
    answer: str
    sources: list[SearchResult]


class ReprocessStaleEmbeddingsResponse(BaseModel):
    """stale_item_count is known synchronously; the re-embedding itself runs in the background."""

    status: str
    stale_item_count: int
