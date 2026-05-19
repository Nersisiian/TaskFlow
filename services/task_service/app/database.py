from typing import AsyncGenerator
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession
from .config import get_settings

settings = get_settings()
write_engine = create_async_engine(
    settings.database_url,
    echo=False,
    pool_size=20,
    max_overflow=10,
    pool_recycle=3600,
    pool_pre_ping=True,
)
read_engine = create_async_engine(
    settings.database_read_url or settings.database_url,
    echo=False,
    pool_size=50,
    max_overflow=20,
    pool_recycle=3600,
    pool_pre_ping=True,
)

WriteSession = async_sessionmaker(write_engine, class_=AsyncSession, expire_on_commit=False)
ReadSession = async_sessionmaker(read_engine, class_=AsyncSession, expire_on_commit=False)


async def get_write_db() -> AsyncGenerator[AsyncSession, None]:
    async with WriteSession() as session:
        yield session


async def get_read_db() -> AsyncGenerator[AsyncSession, None]:
    async with ReadSession() as session:
        yield session
