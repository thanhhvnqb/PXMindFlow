import jwt
from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.core.config import settings

bearer = HTTPBearer()


async def user_id(credentials: HTTPAuthorizationCredentials = Depends(bearer)):
    try:
        claims = jwt.decode(
            credentials.credentials,
            settings.jwt_secret,
            algorithms=["HS256"],
            issuer="mindflow",
            audience="mindflow-client",
        )
        return claims["sub"]
    except (jwt.PyJWTError, KeyError):
        raise HTTPException(401, "invalid_access_token") from None
