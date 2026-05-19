from pydantic_settings import BaseSettings
from functools import lru_cache


class Settings(BaseSettings):
    database_url: str = "postgresql+asyncpg://taskuser:taskpass@postgres:5432/taskdb"
    kafka_bootstrap_servers: str = "kafka:9092"
    task_created_topic: str = "task_created"
    task_updated_topic: str = "task_updated"
    task_deleted_topic: str = "task_deleted"
    redis_url: str = "redis://redis:6379/1"

    class Config:
        env_file = ".env"
        case_sensitive = False


@lru_cache()
def get_settings() -> Settings:
    return Settings()
