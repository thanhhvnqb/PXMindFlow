from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class Credentials(BaseModel):
    email: str = Field(
        min_length=3, max_length=254, pattern=r"^[^\s@]+@[^\s@]+\.[^\s@]+$"
    )
    password: str = Field(min_length=12, max_length=128)


class Tokens(BaseModel):
    user_id: str
    access_token: str
    refresh_token: str


class Refresh(BaseModel):
    refresh_token: str = Field(min_length=20, max_length=200)


class Mutation(BaseModel):
    model_config = ConfigDict(extra="forbid")
    operation_id: UUID
    device_id: UUID
    entity_type: Literal[
        "task_list", "project", "tag", "task", "habit", "habit_checkin", "focus_session"
    ]
    entity_id: UUID
    operation: Literal["create", "update", "delete"]
    base_version: int = Field(ge=0)
    payload: dict


class Push(BaseModel):
    mutations: list[Mutation] = Field(max_length=100)


class PushResult(BaseModel):
    results: list[dict]


class PullResult(BaseModel):
    changes: list[dict]
    next_cursor: int
    has_more: bool
