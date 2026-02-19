"""
Command Center - Database Layer

Uses SQLAlchemy async with aiosqlite for local SQLite storage.
Think of this as your app's memory - even when you restart,
your triage decisions (read/archived/snoozed) are preserved.
"""

import json
from collections.abc import AsyncGenerator
from datetime import UTC, datetime

from sqlalchemy import Boolean, DateTime, String, Text, select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column

from config import settings


class Base(DeclarativeBase):
    pass


class NotificationRecord(Base):
    """Persistent store for notifications and their triage status."""

    __tablename__ = "notifications"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    source: Mapped[str] = mapped_column(String(20))
    source_account: Mapped[str] = mapped_column(String(100))
    source_id: Mapped[str] = mapped_column(String(200), index=True)
    notification_type: Mapped[str] = mapped_column(String(20))
    title: Mapped[str] = mapped_column(String(500))
    body: Mapped[str] = mapped_column(Text, default="")
    sender_name: Mapped[str] = mapped_column(String(200))
    sender_avatar: Mapped[str | None] = mapped_column(String(500), nullable=True)
    timestamp: Mapped[datetime] = mapped_column(DateTime, default=lambda: datetime.now(UTC))
    priority: Mapped[str] = mapped_column(String(10), default="normal")
    triage_status: Mapped[str] = mapped_column(String(10), default="unread", index=True)
    is_actionable: Mapped[bool] = mapped_column(Boolean, default=True)
    thread_id: Mapped[str | None] = mapped_column(String(200), nullable=True)
    channel_name: Mapped[str | None] = mapped_column(String(200), nullable=True)
    project_name: Mapped[str | None] = mapped_column(String(200), nullable=True)
    snoozed_until: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    raw_payload: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=lambda: datetime.now(UTC))


# SECURITY TODO: Encrypt access_token and refresh_token at rest
# using cryptography.fernet with a key from ENV_TOKEN_ENCRYPTION_KEY
class TokenStore(Base):
    """Store OAuth tokens securely (encrypted in production)."""

    __tablename__ = "tokens"

    id: Mapped[str] = mapped_column(String(100), primary_key=True)  # e.g. "gmail:user@email.com"
    service: Mapped[str] = mapped_column(String(20))
    account: Mapped[str] = mapped_column(String(100))
    access_token: Mapped[str] = mapped_column(Text)
    refresh_token: Mapped[str | None] = mapped_column(Text, nullable=True)
    expires_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    extra_data: Mapped[str | None] = mapped_column(Text, nullable=True)


# Database engine and session factory
engine = create_async_engine(settings.database_url, echo=False)
async_session = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)


async def init_db():
    """Create all tables on startup."""
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)


async def get_session() -> AsyncGenerator[AsyncSession, None]:
    """Get a database session."""
    async with async_session() as session:
        yield session


# ============================================================
# Notification CRUD
# ============================================================


async def save_notification(notification) -> None:
    """Save or update a notification in the database.

    Deduplicates by (source, source_id) — if the same message arrives
    again, we update instead of inserting a duplicate.
    """
    async with async_session() as session:
        # Check for existing by source + source_id
        result = await session.execute(
            select(NotificationRecord).where(
                NotificationRecord.source == notification.source.value,
                NotificationRecord.source_id == notification.source_id,
            )
        )
        existing = result.scalar_one_or_none()

        if existing:
            # Update fields that may have changed
            existing.title = notification.title
            existing.body = notification.body
            existing.timestamp = notification.timestamp
            existing.priority = notification.priority.value
        else:
            record = NotificationRecord(
                id=notification.id,
                source=notification.source.value,
                source_account=notification.source_account,
                source_id=notification.source_id,
                notification_type=notification.notification_type.value,
                title=notification.title,
                body=notification.body,
                sender_name=notification.sender_name,
                sender_avatar=notification.sender_avatar,
                timestamp=notification.timestamp,
                priority=notification.priority.value,
                triage_status=notification.triage_status.value,
                is_actionable=notification.is_actionable,
                thread_id=notification.thread_id,
                channel_name=notification.channel_name,
                project_name=notification.project_name,
                raw_payload=json.dumps(notification.raw_payload)
                if notification.raw_payload
                else None,
            )
            session.add(record)

        await session.commit()


async def update_triage_status(
    notification_id: str,
    status: str,
    snoozed_until: datetime | None = None,
) -> bool:
    """Update the triage status of a notification."""
    async with async_session() as session:
        record = await session.get(NotificationRecord, notification_id)
        if not record:
            return False
        record.triage_status = status
        if snoozed_until:
            record.snoozed_until = snoozed_until
        await session.commit()
        return True


async def load_notifications(limit: int = 50, status_filter: str | None = None) -> list[dict]:
    """Load notifications from the database, excluding archived.

    Snoozed notifications reappear when their snooze time has passed.
    """
    async with async_session() as session:
        query = select(NotificationRecord).order_by(NotificationRecord.timestamp.desc())

        if status_filter:
            query = query.where(NotificationRecord.triage_status == status_filter)
        else:
            # Exclude archived by default
            query = query.where(NotificationRecord.triage_status != "archived")

        query = query.limit(limit)
        result = await session.execute(query)
        records = result.scalars().all()

        now = datetime.now(UTC)
        notifications = []
        for r in records:
            # Un-snooze expired items
            if r.triage_status == "snoozed" and r.snoozed_until and r.snoozed_until <= now:
                r.triage_status = "unread"
                r.snoozed_until = None

            notifications.append(
                {
                    "id": r.id,
                    "source": r.source,
                    "source_account": r.source_account,
                    "source_id": r.source_id,
                    "notification_type": r.notification_type,
                    "title": r.title,
                    "body": r.body,
                    "sender_name": r.sender_name,
                    "sender_avatar": r.sender_avatar,
                    "timestamp": r.timestamp.isoformat() if r.timestamp else None,
                    "priority": r.priority,
                    "triage_status": r.triage_status,
                    "is_actionable": r.is_actionable,
                    "thread_id": r.thread_id,
                    "channel_name": r.channel_name,
                    "project_name": r.project_name,
                    "snoozed_until": r.snoozed_until.isoformat() if r.snoozed_until else None,
                    "raw_payload": json.loads(r.raw_payload) if r.raw_payload else None,
                }
            )

        await session.commit()  # Persist any un-snooze updates
        return notifications
