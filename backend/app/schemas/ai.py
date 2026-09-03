from pydantic import BaseModel


class ProcessItemRequest(BaseModel):
    item_id: str


class ProcessItemResponse(BaseModel):
    status: str
    item_id: str
