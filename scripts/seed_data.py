import asyncio
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker
import uuid
from datetime import datetime, timedelta
import sys

sys.path.append("..")
from services.task_service.app.models.task import Task, TaskStatus, TaskPriority
from services.task_service.app.config import get_settings


async def seed():
    settings = get_settings()
    engine = create_async_engine(settings.database_url)
    async_session = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
    async with async_session() as session:
        # Create sample tasks
        tasks = [
            Task(
                title="Set up CI/CD pipeline",
                description="Configure GitHub Actions for automated testing and deployment",
                status=TaskStatus.TODO,
                priority=TaskPriority.HIGH,
                created_by="admin",
                due_date=datetime.utcnow() + timedelta(days=7),
            ),
            Task(
                title="Implement user authentication",
                description="Add JWT-based auth with refresh tokens",
                status=TaskStatus.IN_PROGRESS,
                priority=TaskPriority.HIGH,
                created_by="admin",
                assignee_id="user1",
                due_date=datetime.utcnow() + timedelta(days=3),
            ),
            Task(
                title="Write API documentation",
                description="Complete OpenAPI specs for all services",
                status=TaskStatus.DONE,
                priority=TaskPriority.MEDIUM,
                created_by="admin",
            ),
            Task(
                title="Database optimization",
                description="Add indexes and query caching",
                status=TaskStatus.TODO,
                priority=TaskPriority.MEDIUM,
                created_by="admin",
                due_date=datetime.utcnow() + timedelta(days=14),
            ),
            Task(
                title="Set up monitoring",
                description="Integrate Prometheus and Grafana dashboards",
                status=TaskStatus.TODO,
                priority=TaskPriority.LOW,
                created_by="admin",
            ),
        ]
        for t in tasks:
            session.add(t)
        await session.commit()
        print(f"✅ Seeded {len(tasks)} tasks")


if __name__ == "__main__":
    asyncio.run(seed())
