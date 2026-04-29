from contextlib import asynccontextmanager
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.config import get_settings
from app.middleware.logging import StructuredLoggingMiddleware
from app.routers import health, items, metrics
from app.routers.health import mark_startup_complete
from app.utils.db import init_db, close_db
from app.utils.logger import configure_logging, get_logger

logger = get_logger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings = get_settings()
    configure_logging(log_level=settings.log_level, json=settings.environment != "development")

    logger.info(
        "startup", app=settings.app_name, env=settings.environment, version=settings.app_version
    )

    await init_db(settings.database_url)
    mark_startup_complete()

    logger.info("ready", pod=settings.pod_name, node=settings.node_name)

    yield

    logger.info("shutdown", app=settings.app_name)
    await close_db()


def create_app() -> FastAPI:
    settings = get_settings()

    app = FastAPI(
        title=settings.app_name,
        version=settings.app_version,
        description="Production-grade FastAPI application — Kubernetes deployment guide",
        docs_url="/docs" if settings.debug else None,
        redoc_url="/redoc" if settings.debug else None,
        lifespan=lifespan,
    )

    app.add_middleware(StructuredLoggingMiddleware)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"] if settings.debug else [],
        allow_methods=["GET", "POST", "PATCH", "DELETE"],
        allow_headers=["*"],
    )

    app.include_router(health.router)
    app.include_router(items.router)
    app.include_router(metrics.router)

    @app.exception_handler(Exception)
    async def global_exception_handler(request: Request, exc: Exception):
        logger.error("unhandled_exception", path=request.url.path, error=str(exc))
        return JSONResponse(status_code=500, content={"detail": "Internal server error"})

    return app


app = create_app()
