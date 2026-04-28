import pytest


@pytest.mark.asyncio
async def test_crud_lifecycle(client):
    # Create
    resp = await client.post("/api/v1/items/", json={"name": "Widget", "price": 9.99})
    assert resp.status_code == 201
    item = resp.json()
    item_id = item["id"]
    assert item["name"] == "Widget"
    assert item["price"] == 9.99

    # Read single
    resp = await client.get(f"/api/v1/items/{item_id}")
    assert resp.status_code == 200
    assert resp.json()["name"] == "Widget"

    # List
    resp = await client.get("/api/v1/items/")
    assert resp.status_code == 200
    ids = [i["id"] for i in resp.json()]
    assert item_id in ids

    # Update
    resp = await client.patch(f"/api/v1/items/{item_id}", json={"price": 14.99})
    assert resp.status_code == 200
    assert resp.json()["price"] == 14.99

    # Delete
    resp = await client.delete(f"/api/v1/items/{item_id}")
    assert resp.status_code == 204

    # Confirm gone
    resp = await client.get(f"/api/v1/items/{item_id}")
    assert resp.status_code == 404


@pytest.mark.asyncio
async def test_invalid_price_rejected(client):
    resp = await client.post("/api/v1/items/", json={"name": "Bad", "price": -1})
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_empty_name_rejected(client):
    resp = await client.post("/api/v1/items/", json={"name": "", "price": 5.0})
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_missing_item_returns_404(client):
    resp = await client.get("/api/v1/items/nonexistent-id")
    assert resp.status_code == 404


@pytest.mark.asyncio
async def test_partial_update_keeps_other_fields(client):
    create = await client.post("/api/v1/items/", json={"name": "Gadget", "description": "Cool", "price": 10.0})
    item_id = create.json()["id"]

    update = await client.patch(f"/api/v1/items/{item_id}", json={"price": 20.0})
    body = update.json()
    assert body["name"] == "Gadget"
    assert body["description"] == "Cool"
    assert body["price"] == 20.0
