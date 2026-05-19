from typing import AsyncGenerator, List
from uuid import UUID

from fastapi import APIRouter, Depends, Header, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession

from ...database import get_write_db
from ...events.kafka_producer import KafkaEventProducer
from ...repositories.task_repo import TaskRepository
from ...schemas.task import TaskCreate, TaskOut, TaskUpdate
from ...services.task_service import TaskService

router = APIRouter(prefix="/tasks", tags=["tasks"])


async def get_task_service(
    session: AsyncSession = Depends(get_write_db),
) -> AsyncGenerator[TaskService, None]:
    repo = TaskRepository(session)
    producer = KafkaEventProducer()
    await producer.start()
    try:
        yield TaskService(repo, producer)
    finally:
        await producer.stop()


@router.get("/", response_model=List[TaskOut])
async def list_tasks(
    assignee_id: str = Query(None),
    status: str = Query(None),
    priority: str = Query(None),
    skip: int = Query(0, ge=0),
    limit: int = Query(20, ge=1, le=100),
    sort_by: str = Query("created_at"),
    sort_order: str = Query("desc", regex="^(asc|desc)$"),
    x_user_id: str = Header(..., alias="X-User-ID"),
    service: TaskService = Depends(get_task_service),
):
    tasks = await service.list_tasks(
        assignee_id=assignee_id,
        status=status,
        priority=priority,
        skip=skip,
        limit=limit,
        sort_by=sort_by,
        sort_order=sort_order,
    )
    return tasks


@router.post("/", response_model=TaskOut, status_code=201)
async def create_task(
    task_in: TaskCreate,
    x_user_id: str = Header(..., alias="X-User-ID"),
    service: TaskService = Depends(get_task_service),
):
    return await service.create_task(task_in, user_id=x_user_id)


@router.put("/{task_id}", response_model=TaskOut)
async def update_task(
    task_id: UUID,
    task_update: TaskUpdate,
    x_user_id: str = Header(..., alias="X-User-ID"),
    service: TaskService = Depends(get_task_service),
):
    try:
        return await service.update_task(task_id, task_update)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))


@router.delete("/{task_id}", status_code=204)
async def delete_task(
    task_id: UUID,
    x_user_id: str = Header(..., alias="X-User-ID"),
    service: TaskService = Depends(get_task_service),
):
    try:
        await service.delete_task(task_id)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
