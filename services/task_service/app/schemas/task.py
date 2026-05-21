from datetime import datetime
from typing import Optional
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field

from ..models.task import TaskPriority, TaskStatus


class TaskCreate(BaseModel):
    title: str = Field(..., max_length=200)
    description: Optional[str] = ""
    status: TaskStatus = TaskStatus.TODO
    priority: TaskPriority = TaskPriority.MEDIUM
    assignee_id: Optional[str] = None
    due_date: Optional[datetime] = None


class TaskUpdate(BaseModel):
    title: Optional[str] = None
    description: Optional[str] = None
    status: Optional[TaskStatus] = None
    priority: Optional[TaskPriority] = None
    assignee_id: Optional[str] = None
    due_date: Optional[datetime] = None


class TaskOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    title: str
    description: Optional[str]
    status: TaskStatus
    priority: TaskPriority
    assignee_id: Optional[str]
    created_by: str
    due_date: Optional[datetime]
    created_at: datetime
    updated_at: datetime
