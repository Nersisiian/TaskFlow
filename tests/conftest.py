import pytest_asyncio
from httpx import ASGITransport, AsyncClient

from services.task_service.app.database import Base, engine
from services.task_service.app.main import app


@pytest_asyncio.fixture(scope="session")
async def async_client():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        yield client
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
