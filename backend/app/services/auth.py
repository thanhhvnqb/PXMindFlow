import hashlib
import secrets
from datetime import datetime, timedelta, timezone
from uuid import uuid4

import jwt
from fastapi import HTTPException
from pwdlib import PasswordHash
from sqlalchemy.exc import IntegrityError

from app.core.config import settings
from app.models.entities import RefreshToken, User
from app.repositories import store

passwords = PasswordHash.recommended()


def digest(token):
    return hashlib.sha256(token.encode()).hexdigest()


async def issue(db, user_id):
    now = datetime.now(timezone.utc)
    refresh = secrets.token_urlsafe(48)
    db.add(
        RefreshToken(
            digest=digest(refresh), user_id=user_id, expires_at=now + timedelta(days=30)
        )
    )
    access = jwt.encode(
        {
            "sub": user_id,
            "iat": now,
            "exp": now + timedelta(minutes=15),
            "iss": "mindflow",
            "aud": "mindflow-client",
        },
        settings.jwt_secret,
        algorithm="HS256",
    )
    return {"user_id": user_id, "access_token": access, "refresh_token": refresh}


async def authenticate(db, credentials, register=False):
    email = credentials.email.strip().lower()
    async with db.begin():
        user = await store.by_email(db, email)
        if register:
            if user:
                raise HTTPException(409, "account_exists")
            user = User(
                id=str(uuid4()),
                email=email,
                password_hash=passwords.hash(credentials.password),
                sequence=0,
            )
            db.add(user)
            try:
                await db.flush()
            except IntegrityError:
                raise HTTPException(409, "account_exists") from None
        elif not user or not passwords.verify(credentials.password, user.password_hash):
            raise HTTPException(401, "invalid_credentials")
        return await issue(db, user.id)


async def rotate(db, token):
    async with db.begin():
        from sqlalchemy import select

        row = (
            await db.execute(
                select(RefreshToken)
                .where(RefreshToken.digest == digest(token))
                .with_for_update()
            )
        ).scalar_one_or_none()
        if not row or row.revoked or row.expires_at <= datetime.now(timezone.utc):
            raise HTTPException(401, "invalid_refresh_token")
        row.revoked = True
        return await issue(db, row.user_id)


async def revoke(db, token):
    async with db.begin():
        row = await db.get(RefreshToken, digest(token))
        if row:
            row.revoked = True
    return {"status": "revoked"}
