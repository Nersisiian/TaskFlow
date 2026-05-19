import asyncio
import logging
from .config import Settings
from .consumer import TaskEventConsumer

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


async def main():
    settings = Settings()
    consumer = TaskEventConsumer(settings)
    logger.info("Notification service started, consuming events...")
    await consumer.consume()


if __name__ == "__main__":
    asyncio.run(main())
