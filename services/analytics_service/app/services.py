import json
import logging
from datetime import date
from redis.asyncio import Redis
from .config import get_settings
from .database import async_session
from .repositories import AnalyticsRepository

logger = logging.getLogger(__name__)

class AnalyticsService:
    def __init__(self):
        settings = get_settings()
        self.redis = Redis.from_url(settings.redis_url, decode_responses=True)

    async def daily_task_counts(self):
        async with async_session() as session:
            repo = AnalyticsRepository(session)
            rows = await repo.get_daily_counts()
            for day, created, completed in rows:
                key = f"analytics:daily:{day.isoformat()}"
                await self.redis.hset(key, mapping={
                    "created": created,
                    "completed": completed or 0
                })
            logger.info(f"Aggregated {len(rows)} daily records into Redis")
