from typing import Optional, Any
import aiohttp
from fastapi import HTTPException

class TaskServiceClient:
    def __init__(self, base_url: str):
        self.base_url = base_url

    async def get_tasks(self, user_id: str, params: Optional[dict[str, Any]] = None):
        async with aiohttp.ClientSession() as session:
            headers = {"X-User-ID": user_id}
            async with session.get(f"{self.base_url}/api/v1/tasks", headers=headers, params=params) as resp:
                if resp.status != 200:
                    raise HTTPException(status_code=resp.status, detail="Task service error")
                return await resp.json()

    async def create_task(self, payload: dict, user_id: str):
        async with aiohttp.ClientSession() as session:
            headers = {"X-User-ID": user_id}
            async with session.post(f"{self.base_url}/api/v1/tasks", json=payload, headers=headers) as resp:
                if resp.status != 201:
                    raise HTTPException(status_code=resp.status, detail="Task creation failed")
                return await resp.json()
