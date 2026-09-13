from pydantic import BaseModel

from .search import SearchResult


class ProcessItemRequest(BaseModel):
    item_id: str


class ProcessItemResponse(BaseModel):
    status: str
    item_id: str


class ChatTurn(BaseModel):
    """One earlier turn in the conversation (P2-03, docs/requirements-
    audit-2026-09-13.md) — `role` is `"user"` or `"assistant"`, mirroring
    the mobile app's own `ChatRole`.
    """

    role: str
    text: str


class AskRequest(BaseModel):
    question: str
    limit: int = 8
    # Oldest first, not including `question` itself — see rag_service.
    # answer_question's docstring for how this is used.
    history: list[ChatTurn] = []


class AskResponse(BaseModel):
    question: str
    answer: str
    sources: list[SearchResult]
