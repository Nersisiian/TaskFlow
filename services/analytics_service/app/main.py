from fastapi import FastAPI
import asyncio
from .api.v1 import stats as stats_router
from .scheduler import run_daily_aggregation
from .kafka_consumer import consume_events

app = FastAPI(title="Analytics Service", version="1.0.0")

@app.on_event("startup")
async def startup():
    asyncio.create_task(run_daily_aggregation())
    asyncio.create_task(consume_events())

app.include_router(stats_router.router, prefix="/api/v1")

@app.get("/health")
async def health():
    return {"status": "ok"}
