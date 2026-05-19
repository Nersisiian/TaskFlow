import asyncio
import logging
from .services import AnalyticsService

logger = logging.getLogger(__name__)


async def run_daily_aggregation():
    while True:
        try:
            service = AnalyticsService()
            await service.daily_task_counts()
        except Exception as e:
            logger.error(f"Aggregation job failed: {e}")
        await asyncio.sleep(86400)  # 24 hours
