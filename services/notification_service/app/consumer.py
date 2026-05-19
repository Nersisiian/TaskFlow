import asyncio
import json
from aiokafka import AIOKafkaConsumer
from .config import Settings
from .notifier import send_notification

class TaskEventConsumer:
    def __init__(self, settings: Settings):
        self.settings = settings
        self.consumer = AIOKafkaConsumer(
            settings.task_created_topic,
            settings.task_updated_topic,
            bootstrap_servers=settings.kafka_bootstrap_servers,
            group_id="notification-group",
            value_deserializer=lambda m: json.loads(m.decode('utf-8')),
            auto_offset_reset="earliest",
            enable_auto_commit=True,
        )

    async def consume(self):
        await self.consumer.start()
        try:
            async for msg in self.consumer:
                event = msg.value
                await send_notification(event)
        finally:
            await self.consumer.stop()
