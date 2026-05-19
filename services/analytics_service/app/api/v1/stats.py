from fastapi import APIRouter
from redis.asyncio import Redis

from ...config import get_settings

router = APIRouter(prefix="/stats", tags=["analytics"])


@router.get("/daily/{day}")
async def get_daily_stats(day: str):
    settings = get_settings()
    redis = Redis.from_url(settings.redis_url, decode_responses=True)
    key = f"analytics:daily:{day}"
    data = await redis.hgetall(key)
    await redis.aclose()
    return data if data else {"message": "No data for this day"}
