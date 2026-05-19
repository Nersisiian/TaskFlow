import pytest_asyncio
from httpx import AsyncClient, ASGITransport
from services.task_service.app.main import app
from services.task_service.app.database import engine, Base


@pytest_asyncio.fixture(scope="session")
async def async_client():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        yield client
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
