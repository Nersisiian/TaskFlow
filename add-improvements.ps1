<#
  Adds enterprise improvements to existing TaskFlow platform.
  Run from the project root (taskflow-platform).
#>

$ErrorActionPreference = "Stop"

function Write-File {
    param([string]$Path, [string]$Content)
    $dir = Split-Path $Path -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    # Overwrite only if file does not exist OR if it's a critical file we always want to update
    $overwrite = $false
    if (-not (Test-Path $Path)) {
        $overwrite = $true
    }
    elseif ($Path -match '(config\.py|main\.py|auth\.py|database\.py|docker-compose\.yml|scheduler\.py)$') {
        $overwrite = $true
    }
    if ($overwrite) {
        [System.IO.File]::WriteAllText($Path, $Content, [System.Text.Encoding]::UTF8)
        Write-Host "  ✔ $Path"
    }
    else {
        Write-Host "  ⚠ Skipped (already exists): $Path"
    }
}

Write-Host "🔷 Adding enterprise improvements to TaskFlow Platform ..."

# ==================== GATEWAY ====================
Write-File "services/gateway/app/config.py" @'
from pydantic_settings import BaseSettings
from functools import lru_cache
from typing import List

class Settings(BaseSettings):
    app_name: str = "TaskFlow API Gateway"
    host: str = "0.0.0.0"
    port: int = 8000
    jwt_secret: str = "super-secret-key-change-me"
    jwt_algorithm: str = "HS256"
    access_token_expire_minutes: int = 30
    refresh_token_expire_days: int = 7
    redis_url: str = "redis://redis:6379/0"
    task_service_url: str = "http://task-service:8001"
    internal_api_keys: List[str] = ["dev-key-change-me"]

    class Config:
        env_file = ".env"
        case_sensitive = False

@lru_cache()
def get_settings() -> Settings:
    return Settings()
'@

Write-File "services/gateway/app/security/__init__.py" ''
Write-File "services/gateway/app/security/auth.py" @'
from datetime import datetime, timedelta
from typing import Optional
from jose import JWTError, jwt
from passlib.hash import argon2
from redis.asyncio import Redis
from ..config import get_settings

settings = get_settings()

def verify_password(plain: str, hashed: str) -> bool:
    return argon2.verify(plain, hashed)

def get_password_hash(password: str) -> str:
    return argon2.hash(password)

def create_access_token(data: dict, expires_delta: Optional[timedelta] = None) -> str:
    to_encode = data.copy()
    expire = datetime.utcnow() + (expires_delta or timedelta(minutes=settings.access_token_expire_minutes))
    to_encode.update({"exp": expire, "type": "access"})
    return jwt.encode(to_encode, settings.jwt_secret, algorithm=settings.jwt_algorithm)

def create_refresh_token(data: dict) -> str:
    to_encode = data.copy()
    expire = datetime.utcnow() + timedelta(days=settings.refresh_token_expire_days)
    to_encode.update({"exp": expire, "type": "refresh"})
    return jwt.encode(to_encode, settings.jwt_secret, algorithm=settings.jwt_algorithm)

async def add_token_to_blacklist(redis: Redis, token: str, expire_seconds: int):
    await redis.setex(f"blacklist:{token}", expire_seconds, "1")

async def is_token_blacklisted(redis: Redis, token: str) -> bool:
    return await redis.exists(f"blacklist:{token}") > 0
'@

Write-File "services/gateway/app/security/dependencies.py" @'
from fastapi import Depends, HTTPException, Security, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials, APIKeyHeader
from jose import jwt
from redis.asyncio import Redis
from .auth import is_token_blacklisted
from ..config import Settings, get_settings

bearer_scheme = HTTPBearer()
api_key_header = APIKeyHeader(name="X-API-Key")

async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
    settings: Settings = Depends(get_settings),
    redis: Redis = Depends(get_redis)
) -> dict:
    token = credentials.credentials
    if await is_token_blacklisted(redis, token):
        raise HTTPException(status_code=401, detail="Token revoked")
    try:
        payload = jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
        if payload.get("type") != "access":
            raise HTTPException(status_code=401, detail="Invalid token type")
        return {
            "user_id": payload["sub"],
            "role": payload.get("role", "user"),
            "permissions": payload.get("permissions", [])
        }
    except JWTError:
        raise HTTPException(status_code=401, detail="Could not validate credentials")

async def get_api_key(api_key: str = Security(api_key_header), settings: Settings = Depends(get_settings)):
    if api_key not in settings.internal_api_keys:
        raise HTTPException(status_code=403, detail="Invalid API Key")
    return api_key

def require_permission(permission: str):
    async def perm_checker(current_user: dict = Depends(get_current_user)):
        if permission not in current_user.get("permissions", []):
            raise HTTPException(status_code=403, detail="Insufficient permissions")
        return current_user
    return perm_checker

async def get_redis(settings: Settings = Depends(get_settings)):
    redis = Redis.from_url(settings.redis_url, decode_responses=True)
    try:
        yield redis
    finally:
        await redis.aclose()
'@

Write-File "services/gateway/app/security/rate_limit.py" @'
import time
from fastapi import Request, HTTPException
from starlette.middleware.base import BaseHTTPMiddleware
from redis.asyncio import Redis

class SlidingWindowRateLimiter(BaseHTTPMiddleware):
    def __init__(self, app, redis_url: str, max_requests: int = 100, window_seconds: int = 60):
        super().__init__(app)
        self.redis_url = redis_url
        self.max_requests = max_requests
        self.window = window_seconds

    async def dispatch(self, request: Request, call_next):
        redis = Redis.from_url(self.redis_url, decode_responses=True)
        user = request.headers.get("X-User-ID", "anonymous")
        now = time.time()
        key = f"rate_limit:{user}"
        await redis.zremrangebyscore(key, 0, now - self.window)
        current = await redis.zcard(key)
        if current >= self.max_requests:
            raise HTTPException(status_code=429, detail="Too Many Requests")
        pipe = redis.pipeline()
        pipe.zadd(key, {str(now): now})
        pipe.expire(key, self.window + 1)
        await pipe.execute()
        await redis.aclose()
        return await call_next(request)
'@

Write-File "services/gateway/app/middleware/brute_force.py" @'
from fastapi import Request, HTTPException
from starlette.middleware.base import BaseHTTPMiddleware
from redis.asyncio import Redis

class BruteForceProtection(BaseHTTPMiddleware):
    def __init__(self, app, redis_url: str, max_attempts: int = 5, window: int = 300):
        super().__init__(app)
        self.redis_url = redis_url
        self.max_attempts = max_attempts
        self.window = window

    async def dispatch(self, request: Request, call_next):
        if request.url.path == "/api/v1/auth/login":
            redis = Redis.from_url(self.redis_url, decode_responses=True)
            client_ip = request.client.host
            key = f"brute_force:{client_ip}"
            attempts = await redis.incr(key)
            if attempts == 1:
                await redis.expire(key, self.window)
            if attempts > self.max_attempts:
                raise HTTPException(status_code=429, detail="Too many login attempts.")
            await redis.aclose()
        return await call_next(request)
'@

Write-File "services/gateway/app/middleware/correlation.py" @'
import uuid
from starlette.middleware.base import BaseHTTPMiddleware

class CorrelationIdMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request, call_next):
        correlation_id = request.headers.get("X-Correlation-ID", str(uuid.uuid4()))
        request.state.correlation_id = correlation_id
        response = await call_next(request)
        response.headers["X-Correlation-ID"] = correlation_id
        return response
'@

Write-File "services/gateway/app/observability/__init__.py" ''
Write-File "services/gateway/app/observability/metrics.py" @'
import time
from prometheus_client import Counter, Histogram, generate_latest
from fastapi import Response

REQUEST_COUNT = Counter("http_requests_total", "Total HTTP requests", ["method", "endpoint", "status"])
REQUEST_LATENCY = Histogram("http_request_duration_seconds", "HTTP request latency")

def setup_metrics(app):
    @app.middleware("http")
    async def metrics_middleware(request, call_next):
        method = request.method
        path = request.url.path
        start_time = time.time()
        response = await call_next(request)
        REQUEST_COUNT.labels(method=method, endpoint=path, status=response.status_code).inc()
        REQUEST_LATENCY.observe(time.time() - start_time)
        return response

    @app.get("/metrics")
    async def metrics():
        return Response(content=generate_latest(), media_type="text/plain")
'@

Write-File "services/gateway/app/observability/tracing.py" @'
from opentelemetry import trace
from opentelemetry.exporter.jaeger.thrift import JaegerExporter
from opentelemetry.sdk.resources import SERVICE_NAME, Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor

def init_tracing(app, service_name: str = "gateway"):
    resource = Resource(attributes={SERVICE_NAME: service_name})
    provider = TracerProvider(resource=resource)
    jaeger_exporter = JaegerExporter(agent_host_name="jaeger", agent_port=6831)
    provider.add_span_processor(BatchSpanProcessor(jaeger_exporter))
    trace.set_tracer_provider(provider)
    FastAPIInstrumentor.instrument_app(app)
'@

Write-File "services/gateway/app/observability/logging.py" @'
import logging
from pythonjsonlogger import jsonlogger

class CustomJsonFormatter(jsonlogger.JsonFormatter):
    def add_fields(self, log_record, record, message_dict):
        super().add_fields(log_record, record, message_dict)
        log_record['timestamp'] = record.created
        log_record['level'] = record.levelname
        log_record['service'] = 'gateway'

def setup_logging():
    logger = logging.getLogger()
    handler = logging.StreamHandler()
    formatter = CustomJsonFormatter()
    handler.setFormatter(formatter)
    logger.addHandler(handler)
    logger.setLevel(logging.INFO)
'@

Write-File "services/gateway/app/main.py" @'
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from .middleware.correlation import CorrelationIdMiddleware
from .middleware.brute_force import BruteForceProtection
from .security.rate_limit import SlidingWindowRateLimiter
from .observability.metrics import setup_metrics
from .observability.tracing import init_tracing
from .observability.logging import setup_logging
from .config import get_settings
from .api.v1 import auth, tasks

settings = get_settings()
app = FastAPI(title=settings.app_name, version="1.0.0")

app.add_middleware(CorrelationIdMiddleware)
app.add_middleware(BruteForceProtection, redis_url=settings.redis_url)
app.add_middleware(SlidingWindowRateLimiter, redis_url=settings.redis_url)
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

setup_metrics(app)
init_tracing(app, "gateway")
setup_logging()

app.include_router(auth.router, prefix="/api/v1")
app.include_router(tasks.router, prefix="/api/v1")

@app.get("/health")
async def health():
    return {"status": "ok"}
'@

Write-File "services/gateway/app/api/v1/auth.py" @'
from fastapi import APIRouter, Depends, HTTPException, Body
from pydantic import BaseModel
from redis.asyncio import Redis
from jose import jwt
from ...security.auth import verify_password, get_password_hash, create_access_token, create_refresh_token, add_token_to_blacklist
from ...security.dependencies import get_redis
from ...config import get_settings, Settings

router = APIRouter(prefix="/auth", tags=["auth"])

USERS_DB = {
    "admin": {"password_hash": get_password_hash("adminpass"), "role": "admin", "permissions": ["task:create", "task:read", "task:update", "task:delete"]},
    "user": {"password_hash": get_password_hash("userpass"), "role": "user", "permissions": ["task:read"]}
}

class LoginResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"

@router.post("/login", response_model=LoginResponse)
async def login(
    username: str = Body(...), password: str = Body(...),
    settings: Settings = Depends(get_settings)
):
    user = USERS_DB.get(username)
    if not user or not verify_password(password, user["password_hash"]):
        raise HTTPException(status_code=401, detail="Invalid credentials")
    token_data = {"sub": username, "role": user["role"], "permissions": user["permissions"]}
    access = create_access_token(token_data)
    refresh = create_refresh_token(token_data)
    return {"access_token": access, "refresh_token": refresh, "token_type": "bearer"}

@router.post("/refresh")
async def refresh_token(
    refresh_token: str = Body(..., embed=True),
    settings: Settings = Depends(get_settings),
    redis: Redis = Depends(get_redis)
):
    try:
        payload = jwt.decode(refresh_token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
        if payload.get("type") != "refresh":
            raise HTTPException(status_code=401, detail="Invalid token type")
        user = USERS_DB.get(payload["sub"])
        if not user:
            raise HTTPException(status_code=401)
        new_access = create_access_token({"sub": payload["sub"], "role": user["role"], "permissions": user["permissions"]})
        return {"access_token": new_access, "token_type": "bearer"}
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid refresh token")

@router.post("/logout")
async def logout(
    token: str = Body(..., embed=True),
    redis: Redis = Depends(get_redis),
    settings: Settings = Depends(get_settings)
):
    await add_token_to_blacklist(redis, token, settings.access_token_expire_minutes * 60)
    return {"msg": "Successfully logged out"}
'@

# ==================== TASK SERVICE ====================
Write-File "services/task_service/app/events/__init__.py" ''
Write-File "services/task_service/app/events/kafka_producer.py" @'
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
            max_in_flight_requests_per_connection=1,
        )

    async def start(self):
        await self.producer.start()

    async def stop(self):
        await self.producer.stop()

    async def send_event(self, topic: str, event: dict):
        await self.producer.send_and_wait(topic, event)
'@

Write-File "services/task_service/app/events/kafka_setup.py" @'
from aiokafka import AIOKafkaAdminClient
from aiokafka.admin import NewTopic
from ..config import get_settings

async def create_topics():
    settings = get_settings()
    admin = AIOKafkaAdminClient(bootstrap_servers=settings.kafka_bootstrap_servers)
    await admin.start()
    topics = [
        NewTopic(settings.task_created_topic, num_partitions=3, replication_factor=1),
        NewTopic(settings.task_updated_topic, num_partitions=3, replication_factor=1),
        NewTopic("task_retry", num_partitions=3, replication_factor=1),
        NewTopic("task_dlq", num_partitions=1, replication_factor=1),
    ]
    try:
        await admin.create_topics(topics)
    except Exception:
        pass
    await admin.close()
'@

Write-File "services/task_service/app/events/schemas.py" @'
import uuid
from pydantic import BaseModel, Field
from typing import Literal
from datetime import datetime

class TaskEventV1(BaseModel):
    event_id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    event_type: Literal["task_created", "task_updated"] = "task_created"
    version: int = 1
    task_id: str
    title: str
    status: str
    created_by: str
    timestamp: datetime = Field(default_factory=datetime.utcnow)
'@

Write-File "services/task_service/app/cache/redis_cache.py" @'
import json
from redis.asyncio import Redis
from ..config import get_settings

settings = get_settings()

class RedisCache:
    def __init__(self):
        self.redis = Redis.from_url(settings.redis_url, decode_responses=True)

    async def get(self, key: str):
        return await self.redis.get(key)

    async def set(self, key: str, value, expire: int = 300):
        await self.redis.setex(key, expire, json.dumps(value, default=str))

    async def delete(self, key: str):
        await self.redis.delete(key)

    async def invalidate_pattern(self, pattern: str):
        keys = await self.redis.keys(pattern)
        if keys:
            await self.redis.delete(*keys)
'@

Write-File "services/task_service/app/cache/lock.py" @'
import asyncio
from redis.asyncio import Redis

class RedisLock:
    def __init__(self, redis: Redis, lock_key: str, timeout=10):
        self.redis = redis
        self.lock_key = f"lock:{lock_key}"
        self.timeout = timeout

    async def acquire(self):
        while True:
            if await self.redis.set(self.lock_key, "locked", nx=True, ex=self.timeout):
                return
            await asyncio.sleep(0.1)

    async def release(self):
        await self.redis.delete(self.lock_key)
'@

Write-File "services/task_service/app/cache/pubsub.py" @'
import json
from redis.asyncio import Redis
from ..config import get_settings

async def publish_event(channel: str, message: dict):
    r = Redis.from_url(get_settings().redis_url)
    await r.publish(channel, json.dumps(message))
    await r.aclose()
'@

Write-File "services/task_service/app/database.py" @'
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession
from .config import get_settings

settings = get_settings()
write_engine = create_async_engine(settings.database_url, echo=False, pool_size=20, max_overflow=10, pool_recycle=3600, pool_pre_ping=True)
read_engine = create_async_engine(settings.database_read_url or settings.database_url, echo=False, pool_size=50, max_overflow=20, pool_recycle=3600, pool_pre_ping=True)

WriteSession = async_sessionmaker(write_engine, class_=AsyncSession, expire_on_commit=False)
ReadSession = async_sessionmaker(read_engine, class_=AsyncSession, expire_on_commit=False)

async def get_write_db():
    async with WriteSession() as session:
        yield session

async def get_read_db():
    async with ReadSession() as session:
        yield session
'@

Write-File "services/task_service/app/uow.py" @'
from sqlalchemy.ext.asyncio import AsyncSession
from .repositories.task_repo import TaskRepository

class UnitOfWork:
    def __init__(self, session: AsyncSession):
        self.session = session
        self.tasks = TaskRepository(session)

    async def commit(self):
        await self.session.commit()

    async def rollback(self):
        await self.session.rollback()

    async def __aenter__(self):
        return self

    async def __aexit__(self, exc_type, exc, tb):
        if exc_type:
            await self.rollback()
        else:
            await self.commit()
'@

Write-File "services/task_service/app/models/audit.py" @'
from sqlalchemy import Column, String, DateTime, Text
from sqlalchemy.dialects.postgresql import UUID
from .task import Base
import uuid

class AuditLog(Base):
    __tablename__ = "audit_logs"
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    table_name = Column(String(50))
    record_id = Column(String(36))
    action = Column(String(10))
    changed_by = Column(String(36))
    changes = Column(Text)
    timestamp = Column(DateTime(timezone=True))
'@

# ==================== NOTIFICATION SERVICE ====================
Write-File "services/notification_service/app/idempotent_consumer.py" @'
import json
from aiokafka import AIOKafkaConsumer
from redis.asyncio import Redis

class IdempotentConsumer:
    def __init__(self, topics, group_id, bootstrap_servers, redis_url):
        self.consumer = AIOKafkaConsumer(
            *topics,
            bootstrap_servers=bootstrap_servers,
            group_id=group_id,
            value_deserializer=lambda m: json.loads(m.decode('utf-8')),
            auto_offset_reset="earliest",
            enable_auto_commit=False
        )
        self.redis = Redis.from_url(redis_url, decode_responses=True)

    async def start(self):
        await self.consumer.start()

    async def process(self, handler):
        try:
            async for msg in self.consumer:
                event = msg.value
                event_id = event.get("event_id")
                if event_id and await self.redis.exists(f"processed:{event_id}"):
                    continue
                await handler(event)
                if event_id:
                    await self.redis.setex(f"processed:{event_id}", 3600, "1")
                await self.consumer.commit()
        finally:
            await self.consumer.stop()
            await self.redis.aclose()
'@

Write-File "services/notification_service/app/retry_handler.py" @'
from aiokafka import AIOKafkaProducer
import json
import asyncio

async def retry_with_backoff(producer: AIOKafkaProducer, event: dict, max_retries=3):
    retries = 0
    while retries < max_retries:
        try:
            await asyncio.sleep(0.1)
            return
        except Exception:
            retries += 1
            if retries == max_retries:
                await producer.send_and_wait("task_dlq", json.dumps(event).encode('utf-8'))
            else:
                await producer.send_and_wait("task_retry", json.dumps(event).encode('utf-8'))
                await asyncio.sleep(2 ** retries)
'@

Write-File "services/notification_service/app/main.py" @'
import asyncio
import logging
from .config import Settings
from .idempotent_consumer import IdempotentConsumer
from .notifier import send_notification

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

async def main():
    settings = Settings()
    consumer = IdempotentConsumer(
        [settings.task_created_topic, settings.task_updated_topic],
        group_id="notification-group",
        bootstrap_servers=settings.kafka_bootstrap_servers,
        redis_url=settings.redis_url
    )
    await consumer.start()
    logger.info("Notification service started (idempotent consumer)")
    await consumer.process(send_notification)

if __name__ == "__main__":
    asyncio.run(main())
'@

# ==================== ANALYTICS SERVICE ====================
Write-File "services/analytics_service/app/scheduler.py" @'
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from .services import AnalyticsService

scheduler = AsyncIOScheduler()

async def daily_aggregation_job():
    service = AnalyticsService()
    await service.daily_task_counts()

def start_scheduler():
    scheduler.add_job(daily_aggregation_job, 'interval', hours=24, id='daily_agg')
    scheduler.start()
'@

Write-File "services/analytics_service/app/kafka_consumer.py" @'
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
        value_deserializer=lambda m: json.loads(m.decode('utf-8')),
        auto_offset_reset="earliest",
    )
    await consumer.start()
    try:
        async for msg in consumer:
            pass
    finally:
        await consumer.stop()
'@

Write-File "services/analytics_service/app/main.py" @'
from fastapi import FastAPI
import asyncio
from .api.v1 import stats as stats_router
from .scheduler import start_scheduler
from .kafka_consumer import consume_events

app = FastAPI(title="Analytics Service", version="1.0.0")

@app.on_event("startup")
async def startup():
    start_scheduler()
    asyncio.create_task(consume_events())

app.include_router(stats_router.router, prefix="/api/v1")

@app.get("/health")
async def health():
    return {"status": "ok"}
'@

# ==================== DOCKER & INFRASTRUCTURE ====================
Write-File "deployments/prometheus/prometheus.yml" @'
global:
  scrape_interval: 15s
scrape_configs:
  - job_name: 'gateway'
    static_configs:
      - targets: ['gateway:8000']
  - job_name: 'task-service'
    static_configs:
      - targets: ['task-service:8001']
  - job_name: 'analytics-service'
    static_configs:
      - targets: ['analytics-service:8003']
'@

Write-File "deployments/grafana/datasources/prometheus.yml" @'
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
'@

Write-File "deployments/grafana/dashboards/taskflow-overview.json" @'
{
  "title": "TaskFlow Overview",
  "panels": [
    {
      "type": "graph",
      "title": "Request Rate",
      "targets": [{"expr": "rate(http_requests_total[1m])"}]
    }
  ]
}
'@

Write-File "deployments/k8s/namespace.yaml" @'
apiVersion: v1
kind: Namespace
metadata:
  name: taskflow
'@

Write-File "deployments/k8s/gateway-hpa.yaml" @'
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: gateway-hpa
  namespace: taskflow
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: gateway
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
'@

Write-Host "`n✅ Enterprise improvements added successfully!"