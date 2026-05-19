import json
from aiokafka import AIOKafkaProducer
from ..config import get_settings

class KafkaEventProducer:
    def __init__(self):
        settings = get_settings()
        self.producer = AIOKafkaProducer(
            bootstrap_servers=settings.kafka_bootstrap_servers,
            value_serializer=lambda v: json.dumps(v).encode('utf-8'),
            retry_backoff_ms=500,
        )

    async def start(self):
        await self.producer.start()

    async def stop(self):
        await self.producer.stop()

    async def send_event(self, topic: str, event: dict):
        await self.producer.send_and_wait(topic, event)
