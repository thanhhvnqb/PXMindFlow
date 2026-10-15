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
