from pydantic_settings import BaseSettings, SettingsConfigDict
from functools import lru_cache


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")

    app_name: str = "FastAPI K8s Demo"
    app_version: str = "1.0.0"
    environment: str = "development"
    debug: bool = False

    host: str = "0.0.0.0"
    port: int = 8000
    workers: int = 1

    # Database (example — swap with real DSN in production)
    database_url: str = "sqlite:///./dev.db"

    # Observability
    enable_metrics: bool = True
    log_level: str = "INFO"

    # Kubernetes metadata (injected via Downward API)
    pod_name: str = "unknown"
    pod_namespace: str = "default"
    node_name: str = "unknown"


@lru_cache
def get_settings() -> Settings:
    return Settings()
