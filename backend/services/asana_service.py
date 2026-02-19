"""
Command Center - Asana Service

Connects to Asana for task management (for your specific client).
Polls for task updates and supports creating new tasks.
"""

import asyncio
from datetime import datetime

import httpx

from config import settings
from models.notification import (
    Notification,
    NotificationType,
    Priority,
    Source,
)
from services.base import BaseService


class AsanaService(BaseService):
    """Asana integration for task management."""

    BASE_URL = "https://app.asana.com/api/1.0"

    def __init__(self):
        super().__init__(Source.ASANA, "Asana")
        self._headers = {
            "Authorization": f"Bearer {settings.asana_access_token}",
            "Accept": "application/json",
        }
        self._poll_interval = 30
        self._last_check: datetime | None = None

    async def connect(self) -> bool:
        """Verify Asana credentials."""
        try:
            async with httpx.AsyncClient(timeout=30.0) as client:
                resp = await client.get(
                    f"{self.BASE_URL}/users/me",
                    headers=self._headers,
                )
                resp.raise_for_status()
                user = resp.json()["data"]
                print(f"[Asana] Authenticated as {user['name']}")
                return True
        except Exception as e:
            print(f"[Asana] Connection error: {e}")
            return False

    async def disconnect(self):
        pass

    async def fetch_recent(self, limit: int = 20) -> list[Notification]:
        """Fetch recent tasks assigned to you."""
        notifications = []
        try:
            async with httpx.AsyncClient(timeout=30.0) as client:
                # Get tasks assigned to me
                resp = await client.get(
                    f"{self.BASE_URL}/tasks",
                    headers=self._headers,
                    params={
                        "assignee": "me",
                        "workspace": settings.asana_default_workspace_gid,
                        "opt_fields": "name,notes,due_on,completed,created_at,modified_at,assignee_section.name,projects.name",
                        "completed_since": "now",  # Only incomplete tasks
                        "limit": limit,
                    },
                )
                resp.raise_for_status()
                tasks = resp.json()["data"]

                for task in tasks:
                    notifications.append(self._task_to_notification(task))

        except Exception as e:
            print(f"[Asana] Error fetching tasks: {e}")

        return notifications

    async def listen(self):
        """Poll for task updates."""
        while self._running:
            try:
                async with httpx.AsyncClient(timeout=30.0) as client:
                    params = {
                        "assignee": "me",
                        "workspace": settings.asana_default_workspace_gid,
                        "opt_fields": "name,notes,due_on,completed,created_at,modified_at,projects.name",
                        "completed_since": "now",
                        "limit": 10,
                    }

                    if self._last_check:
                        params["modified_since"] = self._last_check.isoformat()

                    resp = await client.get(
                        f"{self.BASE_URL}/tasks",
                        headers=self._headers,
                        params=params,
                    )
                    resp.raise_for_status()
                    tasks = resp.json()["data"]

                    for task in tasks:
                        notification = self._task_to_notification(task)
                        await self.emit_notification(notification)

                    self._last_check = datetime.utcnow()

            except Exception as e:
                print(f"[Asana] Polling error: {e}")

            await asyncio.sleep(self._poll_interval)

    async def create_task(
        self, title: str, description: str = "", project_gid: str | None = None
    ) -> dict | None:
        """Create a new task in Asana."""
        try:
            project = project_gid or settings.asana_default_project_gid
            async with httpx.AsyncClient(timeout=30.0) as client:
                resp = await client.post(
                    f"{self.BASE_URL}/tasks",
                    headers={**self._headers, "Content-Type": "application/json"},
                    json={
                        "data": {
                            "name": title,
                            "notes": description,
                            "projects": [project],
                            "workspace": settings.asana_default_workspace_gid,
                        }
                    },
                )
                resp.raise_for_status()
                return resp.json()["data"]
        except Exception as e:
            print(f"[Asana] Error creating task: {e}")
            return None

    def _task_to_notification(self, task: dict) -> Notification:
        """Convert an Asana task to unified Notification."""
        projects = [p["name"] for p in task.get("projects", [])]
        project_name = projects[0] if projects else "No Project"

        # Determine priority from due date
        priority = Priority.NORMAL
        if task.get("due_on"):
            due = datetime.strptime(task["due_on"], "%Y-%m-%d")
            days_until = (due - datetime.utcnow()).days
            if days_until < 0:
                priority = Priority.URGENT
            elif days_until <= 2:
                priority = Priority.HIGH

        return Notification(
            source=Source.ASANA,
            source_account="Asana",
            source_id=task["gid"],
            notification_type=NotificationType.TASK_UPDATE,
            title=task.get("name", "Untitled Task"),
            body=task.get("notes", "")[:300],
            sender_name="Asana",
            project_name=project_name,
            priority=priority,
            timestamp=datetime.fromisoformat(
                task.get("modified_at", datetime.utcnow().isoformat()).replace("Z", "+00:00")
            ),
            raw_payload={"due_on": task.get("due_on"), "completed": task.get("completed")},
        )
