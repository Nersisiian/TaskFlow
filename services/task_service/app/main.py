from fastapi import FastAPI
from .api.v1 import tasks as task_router
from .database import engine
from .models.task import Base

app = FastAPI(title="Task Service", version="1.0.0")


@app.on_event("startup")
async def startup():
    # Create tables (for dev; use Alembic in production)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)


app.include_router(task_router.router, prefix="/api/v1")


@app.get("/health")
async def health():
    return {"status": "ok"}
