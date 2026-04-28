import pytest


@pytest.mark.asyncio
async def test_liveness(client):
    resp = await client.get("/healthz/live")
    assert resp.status_code == 200
    assert resp.json()["status"] == "alive"


@pytest.mark.asyncio
async def test_readiness(client):
    resp = await client.get("/healthz/ready")
    assert resp.status_code == 200
    assert resp.json()["status"] == "ready"


@pytest.mark.asyncio
async def test_startup(client):
    resp = await client.get("/healthz/startup")
    assert resp.status_code == 200
    assert resp.json()["status"] == "started"


@pytest.mark.asyncio
async def test_readiness_returns_env_and_version(client):
    resp = await client.get("/healthz/ready")
    body = resp.json()
    assert "environment" in body
    assert "version" in body
