import asyncio
import json
from aiokafka import AIOKafkaConsumer
from .config import get_settings


async def consume_events():
    settings = get_settings()
    consumer = AIOKafkaConsumer(
        settings.task_created_topic,
        settings.task_updated_topic,
        bootstrap_servers=settings.kafka_bootstrap_servers,
        group_id="analytics-group",
        value_deserializer=lambda m: json.loads(m.decode("utf-8")),
        auto_offset_reset="earliest",
    )
    await consumer.start()
    try:
        async for msg in consumer:
            # In real analytics, update counters or trigger recalculations
            pass
    finally:
        await consumer.stop()
