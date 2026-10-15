from datetime import datetime

from sqlalchemy import (
    BigInteger,
    DateTime,
    ForeignKey,
    Integer,
    String,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


class Base(DeclarativeBase):
    pass


class User(Base):
    __tablename__ = "users"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    email: Mapped[str] = mapped_column(String(254), unique=True)
    password_hash: Mapped[str] = mapped_column(String)
    sequence: Mapped[int] = mapped_column(BigInteger, default=0)


class RefreshToken(Base):
    __tablename__ = "refresh_tokens"
    digest: Mapped[str] = mapped_column(String(64), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    revoked: Mapped[bool] = mapped_column(default=False)


class Record(Base):
    __tablename__ = "records"
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), primary_key=True)
    entity_type: Mapped[str] = mapped_column(String(32), primary_key=True)
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    version: Mapped[int] = mapped_column(Integer)
    payload: Mapped[dict] = mapped_column(JSONB)


class Operation(Base):
    __tablename__ = "operations"
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), primary_key=True)
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    fingerprint: Mapped[str] = mapped_column(String(64))
    result: Mapped[dict] = mapped_column(JSONB)


class Change(Base):
    __tablename__ = "sync_changes"
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), primary_key=True)
    sequence: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    record: Mapped[dict] = mapped_column(JSONB)


class AuthRateWindow(Base):
    __tablename__ = "auth_rate_windows"
    key: Mapped[str] = mapped_column(String(64), primary_key=True)
    window: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    count: Mapped[int] = mapped_column(Integer)
