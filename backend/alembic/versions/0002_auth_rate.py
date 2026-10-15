"""Shared auth throttling windows."""
from alembic import op
import sqlalchemy as sa
revision = '0002'
down_revision = '0001'
def upgrade():
    op.create_table('auth_rate_windows', sa.Column('key', sa.String(64), primary_key=True), sa.Column('window', sa.BigInteger(), primary_key=True), sa.Column('count', sa.Integer(), nullable=False))
def downgrade():
    op.drop_table('auth_rate_windows')
