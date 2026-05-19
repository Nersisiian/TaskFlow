import logging
import asyncio

logger = logging.getLogger(__name__)

async def send_notification(event: dict):
    # Mock notification sender
    task_id = event.get("task_id", "unknown")
    logger.info(f"📧 Notification: Event type {event.get('type', 'unknown')} for task {task_id}")
    # Simulate external API call
    await asyncio.sleep(0.1)
