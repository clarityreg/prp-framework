"""
Command Center - Plane Service

Your primary project management tool.
Connects via REST API with polling for updates.
Supports creating issues/tasks directly from the command center.
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


class PlaneService(BaseService):
    """Plane.so integration for project management."""

    def __init__(self):
        super().__init__(Source.PLANE, "Plane")
        self._base_url = settings.plane_api_url.rstrip("/")
        self._headers = {
            "X-API-Key": settings.plane_api_key,
            "Content-Type": "application/json",
        }
        self._workspace = settings.plane_workspace_slug
        self._poll_interval = 30
        self._last_check: datetime | None = None

    async def connect(self) -> bool:
        """Verify Plane API connection."""
        try:
            async with httpx.AsyncClient(timeout=30.0) as client:
                resp = await client.get(
                    f"{self._base_url}/workspaces/{self._workspace}/",
                    headers=self._headers,
                )
                resp.raise_for_status()
                print(f"[Plane] Connected to workspace: {self._workspace}")
                return True
        except Exception as e:
            print(f"[Plane] Connection error: {e}")
            return False

    async def disconnect(self):
        pass

    async def fetch_recent(self, limit: int = 20) -> list[Notification]:
        """Fetch recent issues assigned to you."""
        notifications = []
        try:
            async with httpx.AsyncClient(timeout=30.0) as client:
                # Get issues assigned to me from the default project
                resp = await client.get(
                    f"{self._base_url}/workspaces/{self._workspace}/projects/{settings.plane_default_project_id}/issues/",
                    headers=self._headers,
                    params={
                        "assignees": "me",
                        "order_by": "-updated_at",
                        "per_page": limit,
                    },
                )
                resp.raise_for_status()
                data = resp.json()

                issues = data.get("results", data) if isinstance(data, dict) else data
                if isinstance(issues, list):
                    for issue in issues[:limit]:
                        notifications.append(self._issue_to_notification(issue))

        except Exception as e:
            print(f"[Plane] Error fetching issues: {e}")

        return notifications

    async def listen(self):
        """Poll for issue updates."""
        while self._running:
            try:
                async with httpx.AsyncClient(timeout=30.0) as client:
                    params = {
                        "assignees": "me",
                        "order_by": "-updated_at",
                        "per_page": 10,
                    }

                    if self._last_check:
                        params["updated_at__gte"] = self._last_check.isoformat()

                    resp = await client.get(
                        f"{self._base_url}/workspaces/{self._workspace}/projects/{settings.plane_default_project_id}/issues/",
                        headers=self._headers,
                        params=params,
                    )
                    resp.raise_for_status()
                    data = resp.json()

                    issues = data.get("results", data) if isinstance(data, dict) else data
                    if isinstance(issues, list):
                        for issue in issues:
                            notification = self._issue_to_notification(issue)
                            await self.emit_notification(notification)

                    self._last_check = datetime.utcnow()

            except Exception as e:
                print(f"[Plane] Polling error: {e}")

            await asyncio.sleep(self._poll_interval)

    async def create_issue(
        self,
        title: str,
        description: str = "",
        priority: str = "medium",
        project_id: str | None = None,
    ) -> dict | None:
        """Create a new issue in Plane."""
        try:
            proj = project_id or settings.plane_default_project_id
            async with httpx.AsyncClient(timeout=30.0) as client:
                resp = await client.post(
                    f"{self._base_url}/workspaces/{self._workspace}/projects/{proj}/issues/",
                    headers=self._headers,
                    json={
                        "name": title,
                        "description_html": f"<p>{description}</p>",
                        "priority": priority,
                    },
                )
                resp.raise_for_status()
                return resp.json()
        except Exception as e:
            print(f"[Plane] Error creating issue: {e}")
            return None

    def _issue_to_notification(self, issue: dict) -> Notification:
        """Convert a Plane issue to unified Notification."""
        # Map Plane priority to our priority
        priority_map = {
            "urgent": Priority.URGENT,
            "high": Priority.HIGH,
            "medium": Priority.NORMAL,
            "low": Priority.LOW,
            "none": Priority.LOW,
        }
        priority = priority_map.get(issue.get("priority", "medium"), Priority.NORMAL)

        return Notification(
            source=Source.PLANE,
            source_account="Plane",
            source_id=str(issue.get("id", "")),
            notification_type=NotificationType.TASK_UPDATE,
            title=issue.get("name", "Untitled Issue"),
            body=issue.get("description_stripped", issue.get("description", ""))[:300],
            sender_name="Plane",
            project_name=issue.get("project_detail", {}).get("name", ""),
            priority=priority,
            timestamp=datetime.fromisoformat(
                issue.get("updated_at", datetime.utcnow().isoformat()).replace("Z", "+00:00")
            ),
            raw_payload={
                "state": issue.get("state_detail", {}).get("name"),
                "sequence_id": issue.get("sequence_id"),
                "labels": [label.get("name") for label in issue.get("label_detail", [])],
            },
        )
