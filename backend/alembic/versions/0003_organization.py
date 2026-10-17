"""Compatible Space rename and organization lookup indexes; no record rewrites."""
from alembic import op

revision = "0003"
down_revision = "0002"
branch_labels = None
depends_on = None


def upgrade():
    for key in ("list_id", "space_id", "project_id", "parent_id", "archived_at"):
        op.execute(f"CREATE INDEX records_{key} ON records (user_id, entity_type, (payload->>'{key}'))")


def downgrade():
    for key in ("list_id", "space_id", "project_id", "parent_id", "archived_at"):
        op.drop_index(f"records_{key}", table_name="records")
