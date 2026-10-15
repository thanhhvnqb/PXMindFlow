"""Initial isolated accounts and transactional sync ledger."""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import JSONB
revision = "0001"
down_revision = None

def upgrade():
    op.create_table("users", sa.Column("id", sa.String(36), primary_key=True), sa.Column("email", sa.String(254), nullable=False, unique=True), sa.Column("password_hash", sa.String(), nullable=False), sa.Column("sequence", sa.BigInteger(), nullable=False))
    op.create_table("refresh_tokens", sa.Column("digest", sa.String(64), primary_key=True), sa.Column("user_id", sa.String(36), sa.ForeignKey("users.id"), nullable=False), sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False), sa.Column("revoked", sa.Boolean(), nullable=False))
    op.create_index("ix_refresh_tokens_user_id", "refresh_tokens", ["user_id"])
    op.create_table("records", sa.Column("user_id", sa.String(36), sa.ForeignKey("users.id"), primary_key=True), sa.Column("entity_type", sa.String(32), primary_key=True), sa.Column("id", sa.String(36), primary_key=True), sa.Column("version", sa.Integer(), nullable=False), sa.Column("payload", JSONB(), nullable=False))
    op.create_table("operations", sa.Column("user_id", sa.String(36), sa.ForeignKey("users.id"), primary_key=True), sa.Column("id", sa.String(36), primary_key=True), sa.Column("fingerprint", sa.String(64), nullable=False), sa.Column("result", JSONB(), nullable=False))
    op.create_table("sync_changes", sa.Column("user_id", sa.String(36), sa.ForeignKey("users.id"), primary_key=True), sa.Column("sequence", sa.BigInteger(), primary_key=True), sa.Column("record", JSONB(), nullable=False))

def downgrade():
    for name in ("sync_changes", "operations", "records", "refresh_tokens", "users"):
        op.drop_table(name)
