import time
from fastapi import Request, HTTPException
from starlette.middleware.base import BaseHTTPMiddleware
from redis.asyncio import Redis
from ..config import get_settings

class RateLimitMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        settings = get_settings()
        redis = Redis.from_url(settings.redis_url, decode_responses=True)
        user_id = request.headers.get("X-User-ID", "anonymous")
        key = f"rate_limit:{user_id}"
        current = await redis.get(key)
        if current and int(current) >= 100:
            raise HTTPException(status_code=429, detail="Too many requests")
        pipe = redis.pipeline()
        pipe.incr(key)
        pipe.expire(key, 60)
        await pipe.execute()
        await redis.aclose()
        response = await call_next(request)
        return response
