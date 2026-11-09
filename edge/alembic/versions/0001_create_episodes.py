"""create episodes table

Revision ID: 0001
Revises:
Create Date: 2026-11-08
"""

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision: str = "0001"
down_revision: str | None = None
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "episodes",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("idempotency_key", sa.String(length=128), nullable=False),
        sa.Column("task_id", sa.String(length=128), nullable=False),
        sa.Column("filename", sa.String(length=255), nullable=False),
        sa.Column("size_bytes", sa.BigInteger(), nullable=False),
        sa.Column("checksum_sha256", sa.String(length=64), nullable=False),
        sa.Column("decision", sa.String(length=32), nullable=False),
        sa.Column("reason", sa.Text(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column("manifest", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_episodes_decision",
        "episodes",
        ["decision"],
        unique=False,
    )
    op.create_index(
        "ix_episodes_idempotency_key",
        "episodes",
        ["idempotency_key"],
        unique=True,
    )
    op.create_index(
        "ix_episodes_task_id",
        "episodes",
        ["task_id"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index("ix_episodes_task_id", table_name="episodes")
    op.drop_index("ix_episodes_idempotency_key", table_name="episodes")
    op.drop_index("ix_episodes_decision", table_name="episodes")
    op.drop_table("episodes")
