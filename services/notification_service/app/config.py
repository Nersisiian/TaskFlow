from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    kafka_bootstrap_servers: str = "kafka:9092"
    task_created_topic: str = "task_created"
    task_updated_topic: str = "task_updated"

    class Config:
        env_file = ".env"
