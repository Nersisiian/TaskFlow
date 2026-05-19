from typing import Optional, List, Sequence
from uuid import UUID
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession
from ..models.task import Task, TaskStatus, TaskPriority


class TaskRepository:
    def __init__(self, session: AsyncSession):
        self.session = session

    async def get_by_id(self, task_id: UUID) -> Optional[Task]:
        result = await self.session.execute(select(Task).where(Task.id == task_id))
        return result.scalar_one_or_none()

    async def list_tasks(
        self,
        assignee_id: Optional[str] = None,
        status: Optional[TaskStatus] = None,
        priority: Optional[TaskPriority] = None,
        skip: int = 0,
        limit: int = 20,
        sort_by: str = "created_at",
        sort_order: str = "desc",
    ) -> List[Task]:
        query = select(Task)
        if assignee_id:
            query = query.where(Task.assignee_id == assignee_id)
        if status:
            query = query.where(Task.status == status)
        if priority:
            query = query.where(Task.priority == priority)
        order_col = getattr(Task, sort_by, Task.created_at)
        query = query.order_by(order_col.desc() if sort_order == "desc" else order_col.asc())
        query = query.offset(skip).limit(limit)
        result = await self.session.execute(query)
        return list(result.scalars().all())

    async def create(self, task: Task) -> Task:
        self.session.add(task)
        await self.session.commit()
        await self.session.refresh(task)
        return task

    async def update(self, task: Task) -> Task:
        await self.session.commit()
        await self.session.refresh(task)
        return task

    async def delete(self, task: Task) -> None:
        await self.session.delete(task)
        await self.session.commit()

    async def count_tasks(self, **filters) -> int:
        query = select(func.count()).select_from(Task)
        if filters.get("assignee_id"):
            query = query.where(Task.assignee_id == filters["assignee_id"])
        if filters.get("status"):
            query = query.where(Task.status == filters["status"])
        result = await self.session.execute(query)
        count = result.scalar()
        return count if count is not None else 0
