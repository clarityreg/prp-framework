"""
Command Center - Unified Notification Model

Think of this as a universal adapter: Gmail, Slack, Outlook, Asana, and Plane
all speak different languages, but they all get translated into this one format
before reaching your frontend.
"""

import uuid
from datetime import datetime
from enum import StrEnum
from typing import Literal

from pydantic import BaseModel, Field


class Source(StrEnum):
    GMAIL = "gmail"
    OUTLOOK = "outlook"
    SLACK = "slack"
    ASANA = "asana"
    PLANE = "plane"


class NotificationType(StrEnum):
    EMAIL = "email"
    MESSAGE = "message"
    TASK_UPDATE = "task_update"
    TASK_ASSIGNED = "task_assigned"
    MENTION = "mention"
    COMMENT = "comment"
    REMINDER = "reminder"


class Priority(StrEnum):
    URGENT = "urgent"
    HIGH = "high"
    NORMAL = "normal"
    LOW = "low"


class TriageStatus(StrEnum):
    UNREAD = "unread"
    READ = "read"
    SNOOZED = "snoozed"
    ARCHIVED = "archived"
    ACTIONED = "actioned"


class Notification(BaseModel):
    """The universal notification format. Every service maps to this."""

    id: str = Field(default_factory=lambda: str(uuid.uuid4()))

    # Where it came from
    source: Source
    source_account: str  # e.g. "work@gmail.com" or "Workspace One"
    source_id: str  # Original ID from the service (for reply/actions)

    # What it is
    notification_type: NotificationType
    title: str  # Subject line or message preview
    body: str  # Full content or preview
    sender_name: str
    sender_avatar: str | None = None  # URL to avatar

    # Metadata
    timestamp: datetime = Field(default_factory=datetime.utcnow)
    priority: Priority = Priority.NORMAL
    triage_status: TriageStatus = TriageStatus.UNREAD
    is_actionable: bool = True  # Can we reply/action from the app?

    # For threading / context
    thread_id: str | None = None
    channel_name: str | None = None  # Slack channel or email folder
    project_name: str | None = None  # Asana/Plane project

    # Snooze
    snoozed_until: datetime | None = None

    # Raw payload for service-specific actions
    raw_payload: dict | None = None


class NotificationAction(BaseModel):
    """An action the user wants to take on a notification."""

    notification_id: str
    action: Literal[
        "reply",
        "archive",
        "snooze",
        "mark_read",
        "create_task",
        "open_in_app",
    ]
    payload: dict | None = None  # e.g. {"body": "reply text"} or {"snooze_minutes": 30}


class TaskCreate(BaseModel):
    """Create a task from a notification."""

    title: str
    description: str | None = ""
    target: Literal["plane", "asana"]  # Where to create the task
    priority: Priority = Priority.NORMAL
    project_id: str | None = None  # Override default project
    source_notification_id: str | None = None  # Link back to the notification


class WebSocketMessage(BaseModel):
    """Messages sent over the WebSocket to the frontend."""

    event: Literal[
        "new_notification",
        "notification_updated",
        "notification_removed",
        "connection_status",
        "error",
        "initial_load",
    ]
    data: dict
