from fastapi import APIRouter, HTTPException, status
from typing import Dict
from app.models.item import Item, ItemCreate, ItemUpdate

router = APIRouter(prefix="/api/v1/items", tags=["Items"])

# In-memory store — replace with a real DB layer in production
_store: Dict[str, Item] = {}


@router.post("/", response_model=Item, status_code=status.HTTP_201_CREATED)
async def create_item(payload: ItemCreate) -> Item:
    item = Item(**payload.model_dump())
    _store[item.id] = item
    return item


@router.get("/", response_model=list[Item])
async def list_items() -> list[Item]:
    return list(_store.values())


@router.get("/{item_id}", response_model=Item)
async def get_item(item_id: str) -> Item:
    item = _store.get(item_id)
    if not item:
        raise HTTPException(status_code=404, detail="Item not found")
    return item


@router.patch("/{item_id}", response_model=Item)
async def update_item(item_id: str, payload: ItemUpdate) -> Item:
    item = _store.get(item_id)
    if not item:
        raise HTTPException(status_code=404, detail="Item not found")
    updated = item.model_copy(update=payload.model_dump(exclude_unset=True))
    _store[item_id] = updated
    return updated


@router.delete("/{item_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_item(item_id: str) -> None:
    if item_id not in _store:
        raise HTTPException(status_code=404, detail="Item not found")
    del _store[item_id]
