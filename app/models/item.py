from pydantic import BaseModel, Field
from typing import Optional
import uuid


class ItemCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=100)
    description: Optional[str] = Field(None, max_length=500)
    price: float = Field(..., gt=0)


class Item(ItemCreate):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))

    model_config = {"from_attributes": True}


class ItemUpdate(BaseModel):
    name: Optional[str] = Field(None, min_length=1, max_length=100)
    description: Optional[str] = Field(None, max_length=500)
    price: Optional[float] = Field(None, gt=0)
