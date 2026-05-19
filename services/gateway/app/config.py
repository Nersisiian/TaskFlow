from functools import lru_cache
from typing import List

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    app_name: str = "TaskFlow API Gateway"
    host: str = "0.0.0.0"
    port: int = 8000
    jwt_secret: str = "super-secret-key-change-me"
    jwt_algorithm: str = "HS256"
    access_token_expire_minutes: int = 30
    refresh_token_expire_days: int = 7
    redis_url: str = "redis://redis:6379/0"
    task_service_url: str = "http://task-service:8001"
    internal_api_keys: List[str] = ["dev-key-change-me"]

    class Config:
        env_file = ".env"
        case_sensitive = False


@lru_cache()
def get_settings() -> Settings:
    return Settings()
