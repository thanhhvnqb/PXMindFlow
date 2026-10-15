from sqlalchemy import select

from app.models.entities import Change, Record, User


async def lock_user(db, user_id):
    return (
        await db.execute(select(User).where(User.id == user_id).with_for_update())
    ).scalar_one()


async def by_email(db, email):
    return (
        await db.execute(select(User).where(User.email == email))
    ).scalar_one_or_none()


async def changes(db, user_id, cursor, limit):
    return (
        (
            await db.execute(
                select(Change)
                .where(Change.user_id == user_id, Change.sequence > cursor)
                .order_by(Change.sequence)
                .limit(limit + 1)
            )
        )
        .scalars()
        .all()
    )


async def record(db, user_id, kind, entity_id):
    return await db.get(Record, (user_id, kind, entity_id))
