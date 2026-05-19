from sqlalchemy import Date, cast, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from services.task_service.app.models.task import Task  # import from task service model


class AnalyticsRepository:
    def __init__(self, session: AsyncSession):
        self.session = session

    async def get_daily_counts(self):
        # Complex query aggregating tasks per day
        stmt = (
            select(
                cast(Task.created_at, Date).label("date"),
                func.count().label("created"),
                func.sum(func.case((Task.status == "done", 1), else_=0)).label("completed"),
            )
            .group_by(cast(Task.created_at, Date))
            .order_by(cast(Task.created_at, Date))
        )
        result = await self.session.execute(stmt)
        return result.all()
