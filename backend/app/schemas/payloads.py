from datetime import date, datetime
from typing import Literal
from uuid import UUID
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from pydantic import BaseModel, ConfigDict, Field, field_validator


class Payload(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)


class Named(Payload):
    title: str = Field(min_length=1, max_length=500)

    @field_validator("title")
    @classmethod
    def nonblank(cls, value):
        if not value.strip():
            raise ValueError("blank title")
        return value


class Tagged(Named):
    tag_ids: list[str] = Field(default_factory=list, max_length=100)

    @field_validator("tag_ids")
    @classmethod
    def tags(cls, values):
        for value in values:
            UUID(value)
        if len(values) != len(set(values)):
            raise ValueError("duplicate tag")
        return values


class Archivable(Tagged):
    archived_at: str | None = None

    @field_validator("archived_at")
    @classmethod
    def archive_instant(cls, value):
        if value is not None:
            parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
            if parsed.tzinfo is None or parsed.utcoffset().total_seconds() != 0:
                raise ValueError("archived_at must be UTC")
        return value


class Tag(Named):
    archived_at: str | None = None
    archive_instant = field_validator("archived_at")(
        Archivable.archive_instant.__func__
    )


class Project(Archivable):
    space_id: str
    status: Literal["active", "on_hold", "completed", "cancelled"] = "active"

    @field_validator("space_id")
    @classmethod
    def space_identifier(cls, value):
        UUID(value)
        return value


class TaskList(Archivable):
    color: str | None = Field(default=None, max_length=30)


class Task(Tagged):
    notes: str = Field(default="", max_length=20000)
    list_id: str | None = None
    parent_id: str | None = None
    project_id: str | None = None
    priority: int = Field(default=0, ge=0, le=3)
    due_date: str | None = None
    due_at: str | None = None
    timezone: str = "Etc/UTC"
    completed: bool = False
    is_urgent: bool = False
    is_important: bool = False

    @field_validator("due_at")
    @classmethod
    def due_instant(cls, value):
        if value is not None:
            parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
            if parsed.tzinfo is None or parsed.utcoffset().total_seconds() != 0:
                raise ValueError("due_at must be a UTC instant")
        return value

    @field_validator("list_id", "parent_id", "project_id")
    @classmethod
    def identifier(cls, value):
        if value is not None:
            UUID(value)
        return value

    @field_validator("due_date")
    @classmethod
    def calendar_date(cls, value):
        if value is not None:
            date.fromisoformat(value)
        return value

    @field_validator("timezone")
    @classmethod
    def zone(cls, value):
        try:
            ZoneInfo(value)
        except (ZoneInfoNotFoundError, ValueError):
            raise ValueError("invalid timezone") from None
        return value


class Habit(Named):
    timezone: str = "Etc/UTC"
    target: int = Field(default=1, ge=1, le=10000)
    zone = field_validator("timezone")(Task.zone.__func__)


class Checkin(Payload):
    habit_id: str
    local_date: str
    timezone: str
    count: int = Field(ge=1, le=10000)
    identifier = field_validator("habit_id")(Task.identifier.__func__)
    calendar_date = field_validator("local_date")(Task.calendar_date.__func__)
    zone = field_validator("timezone")(Task.zone.__func__)


class Focus(Named):
    started_at: str
    duration_seconds: int = Field(ge=1, le=86400)
    elapsed_seconds: int = Field(ge=0, le=86400)
    state: Literal["running", "paused", "finished"]
    anchor: str | None
    kind: Literal["focus", "short_break", "long_break"]

    @field_validator("started_at", "anchor")
    @classmethod
    def instant(cls, value):
        if (
            value is not None
            and datetime.fromisoformat(value.replace("Z", "+00:00")).tzinfo is None
        ):
            raise ValueError("timestamp requires timezone")
        return value


SCHEMAS = {
    "task_list": TaskList,
    "project": Project,
    "tag": Tag,
    "task": Task,
    "habit": Habit,
    "habit_checkin": Checkin,
    "focus_session": Focus,
}
