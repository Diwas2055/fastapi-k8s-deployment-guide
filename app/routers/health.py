from fastapi import APIRouter, HTTPException, Depends
from app.config import Settings, get_settings
from app.utils.db import get_db

router = APIRouter(tags=["Health"])

# Startup probe flag — set to True once lifespan init completes
_startup_complete = False


def mark_startup_complete() -> None:
    global _startup_complete
    _startup_complete = True


@router.get("/healthz/startup", summary="Startup probe")
async def startup():
    """
    K8s calls this repeatedly until it returns 200.
    Once it passes, K8s hands off to liveness + readiness.
    Fails with 503 until app init (DB connect, cache warm-up) finishes.
    """
    if not _startup_complete:
        raise HTTPException(status_code=503, detail="Starting up")
    return {"status": "started"}


@router.get("/healthz/live", summary="Liveness probe")
async def liveness():
    """
    Lightweight process check — never touch external dependencies here.
    Failure causes K8s to RESTART the pod. Keep it fast and cheap.
    """
    return {"status": "alive"}


@router.get("/healthz/ready", summary="Readiness probe")
async def readiness(settings: Settings = Depends(get_settings)):
    """
    Full readiness check — DB must be reachable before we accept traffic.
    Failure removes the pod from the Service endpoints WITHOUT restarting it.
    """
    try:
        db = get_db()
        if not await db.ping():
            raise HTTPException(status_code=503, detail="Database not reachable")
    except RuntimeError:
        # DB not yet initialised — still starting
        raise HTTPException(status_code=503, detail="Not ready")

    return {
        "status": "ready",
        "environment": settings.environment,
        "version": settings.app_version,
    }
