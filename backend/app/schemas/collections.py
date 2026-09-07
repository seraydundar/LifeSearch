from pydantic import BaseModel


class SuggestedItem(BaseModel):
    item_id: str
    title: str | None
    item_type: str


class SuggestedCollection(BaseModel):
    suggested_name: str
    items: list[SuggestedItem]


class SuggestCollectionsResponse(BaseModel):
    suggestions: list[SuggestedCollection]
