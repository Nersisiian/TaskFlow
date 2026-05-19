import logging
from typing import List
from uuid import UUID

from ..config import get_settings
from ..events.kafka_producer import KafkaEventProducer
from ..models.task import Task
from ..repositories.task_repo import TaskRepository
from ..schemas.task import TaskCreate, TaskUpdate

logger = logging.getLogger(__name__)
settings = get_settings()


class TaskService:
    def __init__(self, repo: TaskRepository, producer: KafkaEventProducer):
        self.repo = repo
        self.producer = producer

    async def create_task(self, task_data: TaskCreate, user_id: str) -> Task:
        task = Task(
            title=task_data.title,
            description=task_data.description,
            priority=task_data.priority,
            assignee_id=task_data.assignee_id,
            created_by=user_id,
            due_date=task_data.due_date,
        )
        task = await self.repo.create(task)
        await self.producer.send_event(
            settings.task_created_topic,
            {
                "task_id": str(task.id),
                "title": task.title,
                "status": task.status.value,
                "created_by": user_id,
            },
        )
        logger.info(f"Task {task.id} created")
        return task

    async def update_task(self, task_id: UUID, update_data: TaskUpdate) -> Task:
        task = await self.repo.get_by_id(task_id)
        if not task:
            raise ValueError("Task not found")
        for field, value in update_data.dict(exclude_unset=True).items():
            setattr(task, field, value)
        task = await self.repo.update(task)
        await self.producer.send_event(
            settings.task_updated_topic,
            {
                "task_id": str(task.id),
                "status": task.status.value,
            },
        )
        return task

    async def delete_task(self, task_id: UUID) -> None:
        task = await self.repo.get_by_id(task_id)
        if not task:
            raise ValueError("Task not found")
        await self.repo.delete(task)
        await self.producer.send_event(settings.task_deleted_topic, {"task_id": str(task_id)})

    async def list_tasks(self, **filters) -> List[Task]:
        return await self.repo.list_tasks(**filters)
