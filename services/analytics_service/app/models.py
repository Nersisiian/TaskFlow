from sqlalchemy import Column, Date, Integer
from sqlalchemy.orm import DeclarativeBase


class Base(DeclarativeBase):
    pass


class DailyTaskCount(Base):
    __tablename__ = "analytics_daily_counts"

    id = Column(Integer, primary_key=True, autoincrement=True)
    date = Column(Date, nullable=False, unique=True)
    created_count = Column(Integer, default=0)
    completed_count = Column(Integer, default=0)
