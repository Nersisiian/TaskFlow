from fastapi import FastAPI

from .api.v1 import tasks as task_router
from .database import write_engine
from .models.task import Base

app = FastAPI(title="Task Service", version="1.0.0")


@app.on_event("startup")
async def startup():
    async with write_engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)


app.include_router(task_router.router, prefix="/api/v1")


@app.get("/health")
async def health():
    return {"status": "ok"}
