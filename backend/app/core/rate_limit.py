import hashlib
import time

from fastapi import HTTPException, Request
from sqlalchemy.dialects.postgresql import insert

from app.core.config import settings
from app.core.db import Session
from app.models.entities import AuthRateWindow


async def auth_limit(request: Request):
    # Shared PostgreSQL state keeps limits effective across API replicas.
    address = request.client.host if request.client else "unknown"
    key = hashlib.sha256((settings.jwt_secret + address).encode()).hexdigest()
    window = int(time.time()) // 60
    async with Session.begin() as db:
        stmt = insert(AuthRateWindow).values(key=key, window=window, count=1)
        stmt = stmt.on_conflict_do_update(
            index_elements=["key", "window"], set_={"count": AuthRateWindow.count + 1}
        ).returning(AuthRateWindow.count)
        count = (await db.execute(stmt)).scalar_one()
    if count > 60:
        raise HTTPException(429, "auth_rate_limited", headers={"Retry-After": "60"})
