import asyncio
from uuid import uuid4

import pytest
from httpx import ASGITransport, AsyncClient

from app.main import app


@pytest.fixture
async def client():
    async with AsyncClient(
        transport=ASGITransport(app=app), base_url="http://test"
    ) as client:
        yield client
    from app.core.db import engine

    await engine.dispose()


async def account(client):
    response = await client.post(
        "/api/v1/auth/register",
        json={"email": f"{uuid4()}@example.org", "password": "a long test password"},
    )
    assert response.status_code == 201, response.text
    return response.json()


def mutation(
    entity_id=None,
    version=0,
    operation="create",
    title="Plan today",
    kind="task",
    **fields,
):
    return {
        "operation_id": str(uuid4()),
        "device_id": str(uuid4()),
        "entity_type": kind,
        "entity_id": entity_id or str(uuid4()),
        "operation": operation,
        "base_version": version,
        "payload": {"title": title, **fields},
    }


async def push(client, token, *ops):
    response = await client.post(
        "/api/v1/sync/push",
        headers={"Authorization": f"Bearer {token}"},
        json={"mutations": ops},
    )
    assert response.status_code == 200, response.text
    return response.json()["results"]


async def pull(client, token, cursor=0, limit=100):
    response = await client.get(
        "/api/v1/sync/pull",
        headers={"Authorization": f"Bearer {token}"},
        params={"cursor": cursor, "limit": limit},
    )
    assert response.status_code == 200, response.text
    return response.json()


@pytest.mark.asyncio
async def test_lost_ack_idempotency_and_fingerprint(client):
    user = await account(client)
    op = mutation()
    first = (await push(client, user["access_token"], op))[0]
    repeat = (await push(client, user["access_token"], op))[0]
    assert first["record"]["version"] == 1
    assert repeat["duplicate"] and repeat["record"] == first["record"]
    assert len((await pull(client, user["access_token"]))["changes"]) == 1
    op["payload"]["title"] = "different bytes"
    assert (await push(client, user["access_token"], op))[0][
        "code"
    ] == "operation_id_reused"


@pytest.mark.asyncio
@pytest.mark.parametrize("field", ["title", "notes"])
async def test_two_devices_conflict_no_silent_merge(client, field):
    user = await account(client)
    token = user["access_token"]
    create = mutation()
    await push(client, token, create)
    a = mutation(create["entity_id"], 1, "update", "Device A")
    b = mutation(
        create["entity_id"],
        1,
        "update",
        "Plan today",
        **({"notes": "different field"} if field == "notes" else {}),
    )
    results = await asyncio.gather(push(client, token, a), push(client, token, b))
    assert sorted(r[0]["status"] for r in results) == ["applied", "conflict"]
    assert [c["sequence"] for c in (await pull(client, token))["changes"]] == [1, 2]


@pytest.mark.asyncio
async def test_edit_delete_race_and_resolution(client):
    user = await account(client)
    token = user["access_token"]
    create = mutation()
    await push(client, token, create)
    delete = mutation(create["entity_id"], 1, "delete")
    assert (await push(client, token, delete))[0]["status"] == "applied"
    stale = mutation(create["entity_id"], 1, "update", "Local edit")
    conflict = (await push(client, token, stale))[0]
    assert (
        conflict["status"] == "conflict" and conflict["record"]["payload"]["deleted_at"]
    )
    resurrection = mutation(create["entity_id"], 2, "update", "Resurrect")
    assert (await push(client, token, resurrection))[0]["status"] == "conflict"
    assert (await push(client, token, delete))[0]["duplicate"]


@pytest.mark.asyncio
async def test_pagination_concurrent_publish_and_isolation(client):
    a, b = await account(client), await account(client)
    ops = [mutation() for _ in range(8)]
    await asyncio.gather(*(push(client, a["access_token"], op) for op in ops))
    cursor = 0
    sequences = []
    while True:
        page = await pull(client, a["access_token"], cursor, 3)
        sequences.extend(c["sequence"] for c in page["changes"])
        cursor = page["next_cursor"]
        if not page["has_more"]:
            break
    assert sequences == list(range(1, 9))
    assert not (await pull(client, b["access_token"]))["changes"]
    guessed = mutation(ops[0]["entity_id"], 1, "update", "Attack")
    assert (await push(client, b["access_token"], guessed))[0]["status"] == "conflict"
    foreign_list = mutation(kind="task_list")
    await push(client, a["access_token"], foreign_list)
    assert (
        await push(
            client, b["access_token"], mutation(list_id=foreign_list["entity_id"])
        )
    )[0]["code"] == "invalid_reference"


@pytest.mark.asyncio
async def test_partial_batch_and_offline_dependency_order(client):
    user = await account(client)
    project = mutation(kind="task_list")
    task = mutation(list_id=project["entity_id"])
    bad = mutation(title="")
    result = await push(client, user["access_token"], project, task, bad)
    assert [r["status"] for r in result] == ["applied", "applied", "validation_failure"]
    assert len((await pull(client, user["access_token"]))["changes"]) == 2


@pytest.mark.asyncio
async def test_refresh_rotation_revocation_and_auth_required(client):
    user = await account(client)
    response = await client.post(
        "/api/v1/auth/refresh", json={"refresh_token": user["refresh_token"]}
    )
    assert response.status_code == 200
    assert (
        await client.post(
            "/api/v1/auth/refresh", json={"refresh_token": user["refresh_token"]}
        )
    ).status_code == 401
    new = response.json()
    await client.post(
        "/api/v1/auth/logout", json={"refresh_token": new["refresh_token"]}
    )
    assert (
        await client.post(
            "/api/v1/auth/refresh", json={"refresh_token": new["refresh_token"]}
        )
    ).status_code == 401
    assert (await client.get("/api/v1/sync/pull")).status_code in (401, 403)


@pytest.mark.asyncio
async def test_habit_checkin_identity_and_duplicates(client):
    from uuid import NAMESPACE_URL, uuid5

    user = await account(client)
    token = user["access_token"]
    habit = mutation(kind="habit", timezone="Etc/UTC", target=1)
    await push(client, token, habit)
    key = str(uuid5(NAMESPACE_URL, f"{habit['entity_id']}/2026-10-13/Etc/UTC"))
    check = mutation(
        key,
        kind="habit_checkin",
        habit_id=habit["entity_id"],
        local_date="2026-10-13",
        timezone="Etc/UTC",
        count=1,
    )
    check["payload"].pop("title")
    assert (await push(client, token, check))[0]["status"] == "applied"
    other = {**check, "operation_id": str(uuid4()), "device_id": str(uuid4())}
    assert (await push(client, token, other))[0]["status"] == "conflict"
    assert len((await pull(client, token))["changes"]) == 2


@pytest.mark.asyncio
async def test_invalid_types_do_not_become_server_errors(client):
    user = await account(client)
    invalid = [
        mutation(list_id=123),
        mutation(completed="true"),
        mutation(priority=9),
        mutation(timezone="not/a-zone"),
    ]
    results = await push(client, user["access_token"], *invalid)
    assert all(r["status"] == "validation_failure" for r in results)


@pytest.mark.asyncio
async def test_timed_task_survives_push_pull_and_date_only_update(client):
    user = await account(client)
    token = user["access_token"]
    op = mutation(due_date="2026-10-17", due_at="2026-10-17T07:00:00.000Z")
    result = (await push(client, token, op))[0]
    assert result["status"] == "applied"
    page = await pull(client, token)
    assert (
        page["changes"][0]["record"]["payload"]["due_at"] == "2026-10-17T07:00:00.000Z"
    )
    update = mutation(
        entity_id=op["entity_id"],
        version=1,
        operation="update",
        due_date="2026-10-17",
        due_at=None,
    )
    assert (await push(client, token, update))[0]["status"] == "applied"
    page = await pull(client, token, cursor=page["next_cursor"])
    assert page["changes"][0]["record"]["payload"]["due_at"] is None


def test_task_due_at_requires_utc():
    from pydantic import ValidationError

    from app.schemas.payloads import Task

    for value in ["invalid", "2026-10-17T14:00:00", "2026-10-17T14:00:00+07:00"]:
        with pytest.raises(ValidationError):
            Task(title="Timed", due_at=value)
    assert Task(title="Date only").due_at is None


@pytest.mark.asyncio
async def test_organization_ownership_context_archive_and_cycles(client):
    user = await account(client)
    other = await account(client)
    token = user["access_token"]
    tag = mutation(kind="tag")
    space = mutation(kind="task_list", tag_ids=[tag["entity_id"]])
    project = mutation(kind="project", space_id=space["entity_id"], status="on_hold")
    task = mutation(project_id=project["entity_id"])
    child = mutation(parent_id=task["entity_id"])
    results = await push(client, token, tag, space, project, task, child)
    assert all(r["status"] == "applied" for r in results)
    for op in [
        mutation(kind="project", space_id=space["entity_id"]),
        mutation(project_id=project["entity_id"]),
        mutation(tag_ids=[tag["entity_id"]]),
        mutation(parent_id=task["entity_id"]),
    ]:
        result = (await push(client, other["access_token"], op))[0]
        assert result["code"] == "invalid_reference"
    mixed = mutation(list_id=space["entity_id"], project_id=project["entity_id"])
    assert (await push(client, token, mixed))[0]["code"] == "ambiguous_task_context"
    cycle = mutation(
        entity_id=task["entity_id"],
        version=1,
        operation="update",
        parent_id=child["entity_id"],
    )
    assert (await push(client, token, cycle))[0]["code"] == "task_cycle"
    for op in [space, project, task, tag]:
        deletion = mutation(
            entity_id=op["entity_id"],
            kind=op["entity_type"],
            version=1,
            operation="delete",
        )
        assert (await push(client, token, deletion))[0]["code"] == "record_in_use"
    for op in [tag, space, project]:
        fields = {k: v for k, v in op["payload"].items() if k != "title"}
        archived = mutation(
            entity_id=op["entity_id"],
            kind=op["entity_type"],
            version=1,
            operation="update",
            **fields,
            archived_at="2026-10-17T10:00:00Z",
        )
        assert (await push(client, token, archived))[0]["status"] == "applied"
        restored = mutation(
            entity_id=op["entity_id"],
            kind=op["entity_type"],
            version=2,
            operation="update",
            **fields,
            archived_at=None,
        )
        assert (await push(client, token, restored))[0]["status"] == "applied"
    changes = (await pull(client, token))["changes"]
    child_changes = [c for c in changes if c["record"]["id"] == child["entity_id"]]
    assert len(child_changes) == 1
    assert child_changes[0]["record"]["payload"]["parent_id"] == task["entity_id"]
    assert (await pull(client, other["access_token"]))["changes"] == []


@pytest.mark.asyncio
async def test_invalid_update_returns_server_snapshot_and_fresh_retry_succeeds(client):
    user = await account(client)
    token = user["access_token"]
    original = mutation()
    await push(client, token, original)
    invalid = mutation(
        entity_id=original["entity_id"], version=1, operation="update", priority=99
    )
    rejection = (await push(client, token, invalid))[0]
    assert rejection["code"] == "invalid_payload"
    assert rejection["record"]["version"] == 1
    assert (await push(client, token, invalid))[0]["duplicate"]
    retry = mutation(
        entity_id=original["entity_id"],
        version=1,
        operation="update",
        title="Keep my edit",
        project_id=None,
        parent_id=None,
    )
    result = (await push(client, token, retry))[0]
    assert result["status"] == "applied"
    assert result["record"]["version"] == 2
