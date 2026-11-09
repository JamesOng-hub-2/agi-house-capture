"""add gate and cloud state

Revision ID: 0002
Revises: 0001
Create Date: 2026-11-08
"""

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision: str = "0002"
down_revision: str | None = "0001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "episodes",
        sa.Column(
            "gate_version",
            sa.String(length=128),
            server_default="legacy-basic-gate",
            nullable=False,
        ),
    )
    op.add_column(
        "episodes",
        sa.Column(
            "gate_details",
            postgresql.JSONB(astext_type=sa.Text()),
            server_default=sa.text("'{}'::jsonb"),
            nullable=False,
        ),
    )
    op.add_column(
        "episodes",
        sa.Column(
            "cloud_status",
            sa.String(length=32),
            server_default="not_approved",
            nullable=False,
        ),
    )
    op.add_column(
        "episodes",
        sa.Column("cloud_path", sa.String(length=512), nullable=True),
    )
    op.add_column(
        "episodes",
        sa.Column(
            "uploaded_at",
            sa.DateTime(timezone=True),
            nullable=True,
        ),
    )


def downgrade() -> None:
    op.drop_column("episodes", "uploaded_at")
    op.drop_column("episodes", "cloud_path")
    op.drop_column("episodes", "cloud_status")
    op.drop_column("episodes", "gate_details")
    op.drop_column("episodes", "gate_version")
