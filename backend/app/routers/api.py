from fastapi import APIRouter, Depends, Query

from app.core.db import session
from app.core.rate_limit import auth_limit
from app.core.security import user_id
from app.schemas.contracts import (
    Credentials,
    PullResult,
    Push,
    PushResult,
    Refresh,
    Tokens,
)
from app.services import auth, sync

router = APIRouter(prefix="/api/v1")


@router.post("/auth/register", response_model=Tokens, status_code=201)
async def register(body: Credentials, db=Depends(session), limited=Depends(auth_limit)):
    return await auth.authenticate(db, body, True)


@router.post("/auth/login", response_model=Tokens)
async def login(body: Credentials, db=Depends(session), limited=Depends(auth_limit)):
    return await auth.authenticate(db, body)


@router.post("/auth/refresh", response_model=Tokens)
async def refresh(body: Refresh, db=Depends(session), limited=Depends(auth_limit)):
    return await auth.rotate(db, body.refresh_token)


@router.post("/auth/logout", response_model=dict)
async def logout(body: Refresh, db=Depends(session)):
    return await auth.revoke(db, body.refresh_token)


@router.post("/sync/push", response_model=PushResult)
async def push(body: Push, uid=Depends(user_id), db=Depends(session)):
    return await sync.push(db, uid, body.mutations)


@router.get("/sync/pull", response_model=PullResult)
async def pull(
    cursor: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=500),
    uid=Depends(user_id),
    db=Depends(session),
):
    return await sync.pull(db, uid, cursor, limit)
