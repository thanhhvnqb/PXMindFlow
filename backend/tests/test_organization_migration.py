"""Exercise the additive migration with legacy data in a rolled-back schema."""

import runpy
from uuid import uuid4

import pytest
from alembic.migration import MigrationContext
from alembic.operations import Operations
from sqlalchemy import text

from app.core.db import engine


@pytest.mark.asyncio
async def test_organization_migration_preserves_legacy_payloads_and_versions():
    schema = f"migration_probe_{uuid4().hex}"
    async with engine.connect() as connection:
        transaction = await connection.begin()
        try:
            await connection.execute(text(f'CREATE SCHEMA "{schema}"'))
            await connection.execute(text(f'SET LOCAL search_path TO "{schema}"'))
            await connection.execute(
                text(
                    "CREATE TABLE records (user_id text, entity_type text, id text, version integer, payload jsonb)"
                )
            )
            await connection.execute(
                text(
                    "INSERT INTO records VALUES ('owner', 'task_list', 'space', 7, '{\"title\": \"Legacy\"}'), "
                    "('owner', 'task', 'task', 9, '{\"title\": \"Unsent\", \"list_id\": \"space\"}')"
                )
            )
            before = (
                await connection.execute(text("SELECT * FROM records ORDER BY id"))
            ).all()

            def upgrade(sync_connection):
                migration = runpy.run_path("alembic/versions/0003_organization.py")
                with Operations.context(MigrationContext.configure(sync_connection)):
                    migration["upgrade"]()

            await connection.run_sync(upgrade)
            after = (
                await connection.execute(text("SELECT * FROM records ORDER BY id"))
            ).all()
            assert after == before
            count = await connection.scalar(
                text(
                    "SELECT count(*) FROM pg_indexes WHERE schemaname = :schema AND indexname LIKE 'records_%'"
                ),
                {"schema": schema},
            )
            assert count == 5
        finally:
            await transaction.rollback()
    await engine.dispose()
