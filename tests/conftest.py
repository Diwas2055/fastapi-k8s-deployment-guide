import pytest
from httpx import AsyncClient, ASGITransport

from app.main import app
from app.utils.db import init_db, close_db
from app.routers.health import mark_startup_complete


@pytest.fixture(autouse=True)
async def setup_db():
    """Initialise the DB stub and mark startup complete for every test."""
    await init_db("sqlite:///./test.db")
    mark_startup_complete()
    yield
    await close_db()


@pytest.fixture
async def client():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as c:
        yield c
