import hashlib
import json
from datetime import datetime, timezone
from uuid import NAMESPACE_URL, uuid5

from fastapi import HTTPException
from pydantic import ValidationError
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.entities import Change, Operation, Record
from app.repositories import store
from app.schemas.contracts import Mutation
from app.schemas.payloads import SCHEMAS


def snapshot(row):
    return {
        "id": row.id,
        "entity_type": row.entity_type,
        "version": row.version,
        "payload": row.payload,
    }


async def validate(
    db: AsyncSession, uid: str, kind: str, payload: dict, entity_id: str | None = None
) -> str | None:
    try:
        SCHEMAS[kind].model_validate(payload)
    except (ValidationError, ValueError, TypeError):
        return "invalid_payload"
    if len(json.dumps(payload)) > 32000:
        return "payload_too_large"
    for key, related in (
        ("list_id", "task_list"),
        ("space_id", "task_list"),
        ("project_id", "project"),
        ("parent_id", "task"),
        ("habit_id", "habit"),
    ):
        if payload.get(key):
            parent = await store.record(db, uid, related, payload[key])
            if not parent or parent.payload.get("deleted_at"):
                return "invalid_reference"
    for tag_id in payload.get("tag_ids", []):
        tag = await store.record(db, uid, "tag", tag_id)
        if not tag or tag.payload.get("deleted_at"):
            return "invalid_reference"
    if kind == "task":
        if (
            sum(bool(payload.get(k)) for k in ("list_id", "project_id", "parent_id"))
            > 1
        ):
            return "ambiguous_task_context"
        seen = {entity_id}
        parent_id = payload.get("parent_id")
        while parent_id:
            if parent_id in seen:
                return "task_cycle"
            seen.add(parent_id)
            parent = await store.record(db, uid, "task", parent_id)
            if not parent or parent.payload.get("deleted_at"):
                return "invalid_reference"
            parent_id = parent.payload.get("parent_id")
    return None


async def referenced(db: AsyncSession, uid: str, kind: str, entity_id: str) -> bool:
    keys = {
        "task_list": ("list_id", "space_id"),
        "project": ("project_id",),
        "task": ("parent_id",),
        "tag": ("tag_ids",),
    }.get(kind, ())
    if not keys:
        return False
    rows = (await db.scalars(select(Record).where(Record.user_id == uid))).all()
    return any(
        not r.payload.get("deleted_at")
        and any(
            entity_id in r.payload.get(k, [])
            if k == "tag_ids"
            else r.payload.get(k) == entity_id
            for k in keys
        )
        for r in rows
    )


async def push(db: AsyncSession, uid: str, mutations: list[Mutation]) -> dict:
    results = []
    async with db.begin():
        # Per-account row lock serializes record updates AND publication ordering.
        # Sequence allocation cannot overtake an uncommitted writer.
        user = await store.lock_user(db, uid)
        for mutation in mutations:
            op_id = str(mutation.operation_id)
            encoded = json.dumps(mutation.model_dump(mode="json"), sort_keys=True)
            fingerprint = hashlib.sha256(encoded.encode()).hexdigest()
            previous = await db.get(Operation, (uid, op_id))
            if previous:
                if previous.fingerprint != fingerprint:
                    results.append(
                        {
                            "operation_id": op_id,
                            "status": "validation_failure",
                            "code": "operation_id_reused",
                        }
                    )
                else:
                    results.append({**previous.result, "duplicate": True})
                continue
            entity_id = str(mutation.entity_id)
            row = await store.record(db, uid, mutation.entity_type, entity_id)
            current = row.version if row else 0
            result = {"operation_id": op_id}
            if (
                current != mutation.base_version
                or (row and mutation.operation == "create")
                or (not row and mutation.operation != "create")
                or (
                    row
                    and row.payload.get("deleted_at")
                    and mutation.operation != "delete"
                )
            ):
                result.update(status="conflict", record=snapshot(row) if row else None)
            elif (
                mutation.entity_type == "habit_checkin"
                and mutation.operation != "delete"
                and str(
                    uuid5(
                        NAMESPACE_URL,
                        f"{mutation.payload.get('habit_id')}/{mutation.payload.get('local_date')}/{mutation.payload.get('timezone')}",
                    )
                )
                != entity_id
            ):
                result.update(
                    status="validation_failure", code="invalid_checkin_identity"
                )
            else:
                error = (
                    None
                    if mutation.operation == "delete"
                    else await validate(
                        db, uid, mutation.entity_type, mutation.payload, entity_id
                    )
                )
                if mutation.operation == "delete" and await referenced(
                    db, uid, mutation.entity_type, entity_id
                ):
                    error = "record_in_use"
                if error:
                    result.update(
                        status="validation_failure",
                        code=error,
                        record=snapshot(row) if row else None,
                    )
                else:
                    now = datetime.now(timezone.utc).isoformat()
                    payload = dict(
                        row.payload
                        if mutation.operation == "delete"
                        else mutation.payload
                    )
                    payload.update(
                        created_at=row.payload["created_at"] if row else now,
                        updated_at=now,
                        deleted_at=now if mutation.operation == "delete" else None,
                    )
                    if row:
                        row.payload = payload
                        row.version += 1
                    else:
                        row = Record(
                            user_id=uid,
                            entity_type=mutation.entity_type,
                            id=entity_id,
                            version=1,
                            payload=payload,
                        )
                        db.add(row)
                    user.sequence += 1
                    canonical = snapshot(row)
                    db.add(
                        Change(user_id=uid, sequence=user.sequence, record=canonical)
                    )
                    result.update(status="applied", record=canonical)
            db.add(
                Operation(user_id=uid, id=op_id, fingerprint=fingerprint, result=result)
            )
            await db.flush()
            results.append(result)
    return {"results": results}


async def pull(db: AsyncSession, uid: str, cursor: int, limit: int) -> dict:
    user = await db.get(__import__("app.models.entities", fromlist=["User"]).User, uid)
    if cursor > user.sequence:
        raise HTTPException(409, "cursor_ahead")
    rows = await store.changes(db, uid, cursor, limit)
    page = rows[:limit]
    return {
        "changes": [{"sequence": r.sequence, "record": r.record} for r in page],
        "next_cursor": page[-1].sequence if page else cursor,
        "has_more": len(rows) > limit,
    }
