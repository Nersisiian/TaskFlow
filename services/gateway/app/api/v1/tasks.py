from fastapi import APIRouter, Depends, Request
from ...dependencies import get_current_user, require_role
from ...services.task_client import TaskServiceClient
from ...config import get_settings

router = APIRouter(prefix="/tasks", tags=["tasks"])

async def get_task_client() -> TaskServiceClient:
    settings = get_settings()
    return TaskServiceClient(settings.task_service_url)

@router.get("/")
async def list_tasks(
    request: Request,
    client: TaskServiceClient = Depends(get_task_client),
    current_user: dict = Depends(get_current_user)
):
    # Forward query params
    params = dict(request.query_params)
    return await client.get_tasks(user_id=current_user["user_id"], params=params)

@router.post("/", status_code=201)
async def create_task(
    payload: dict,
    client: TaskServiceClient = Depends(get_task_client),
    current_user: dict = Depends(require_role("admin"))
):
    return await client.create_task(payload, user_id=current_user["user_id"])
