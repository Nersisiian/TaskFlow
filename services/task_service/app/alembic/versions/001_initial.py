"""initial

Revision ID: 001
Revises:
Create Date: 2025-01-01
"""

import sqlalchemy as sa
from alembic import op

revision = "001"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "tasks",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("title", sa.String(200), nullable=False),
        sa.Column("description", sa.Text(), server_default=""),
        sa.Column(
            "status",
            sa.Enum("todo", "in_progress", "done", name="taskstatus"),
            nullable=False,
            server_default="todo",
        ),
        sa.Column(
            "priority",
            sa.Enum("low", "medium", "high", name="taskpriority"),
            nullable=False,
            server_default="medium",
        ),
        sa.Column("assignee_id", sa.String(36), nullable=True),
        sa.Column("created_by", sa.String(36), nullable=False),
        sa.Column("due_date", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            onupdate=sa.func.now(),
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_tasks_assignee_id", "tasks", ["assignee_id"])
    op.create_index("ix_tasks_status_priority", "tasks", ["status", "priority"])
    op.create_index("ix_tasks_created_by", "tasks", ["created_by"])


def downgrade() -> None:
    op.drop_index("ix_tasks_created_by", table_name="tasks")
    op.drop_index("ix_tasks_status_priority", table_name="tasks")
    op.drop_index("ix_tasks_assignee_id", table_name="tasks")
    op.drop_table("tasks")
    op.execute("DROP TYPE taskstatus")
    op.execute("DROP TYPE taskpriority")
