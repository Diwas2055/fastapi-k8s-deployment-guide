"""
Lightweight database connectivity helper.
Swap the engine/session logic for SQLAlchemy, asyncpg, or any ORM you prefer.
"""
import asyncio
from typing import Optional


class DatabaseClient:
    """Thin async wrapper — replace with real DB driver in production."""

    def __init__(self, url: str) -> None:
        self.url = url
        self._connected = False

    async def connect(self) -> None:
        # Replace with: await engine.connect() or pool.acquire()
        await asyncio.sleep(0)
        self._connected = True

    async def disconnect(self) -> None:
        await asyncio.sleep(0)
        self._connected = False

    async def ping(self) -> bool:
        """Used by the readiness probe — returns True when DB is reachable."""
        if not self._connected:
            return False
        # Replace with: await conn.execute(text("SELECT 1"))
        return True

    @property
    def is_connected(self) -> bool:
        return self._connected


# Module-level singleton — initialised during app lifespan
_db: Optional[DatabaseClient] = None


def get_db() -> DatabaseClient:
    if _db is None:
        raise RuntimeError("Database client not initialised — call init_db() first")
    return _db


async def init_db(url: str) -> DatabaseClient:
    global _db
    _db = DatabaseClient(url)
    await _db.connect()
    return _db


async def close_db() -> None:
    global _db
    if _db is not None:
        await _db.disconnect()
        _db = None
