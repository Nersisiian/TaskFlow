import pytest
from httpx import AsyncClient

@pytest.mark.asyncio
async def test_create_task(async_client: AsyncClient):
    payload = {"title": "New Task", "description": "test"}
    headers = {"X-User-ID": "admin"}
    response = await async_client.post("/api/v1/tasks/", json=payload, headers=headers)
    assert response.status_code == 201
    data = response.json()
    assert data["title"] == "New Task"
    assert data["status"] == "todo"
