"""
Command Center - Outlook Service

Connects to Outlook/Exchange via Microsoft Graph API.
Uses delta queries for efficient polling of new emails.
In production, you'd set up Graph webhooks for real-time push.
"""

import asyncio
from datetime import datetime

import httpx
import msal

from config import settings
from models.notification import (
    Notification,
    NotificationType,
    Source,
)
from services.base import BaseService


class OutlookService(BaseService):
    """Microsoft Outlook integration via Graph API."""

    GRAPH_BASE = "https://graph.microsoft.com/v1.0"
    SCOPES = ["https://graph.microsoft.com/Mail.ReadWrite"]

    def __init__(self):
        super().__init__(Source.OUTLOOK, settings.outlook_account)
        self._access_token: str | None = None
        self._msal_app = None
        self._delta_link: str | None = None
        self._poll_interval = 30

    async def connect(self) -> bool:
        """Authenticate with Microsoft via MSAL."""
        try:
            self._msal_app = msal.ConfidentialClientApplication(
                settings.ms_client_id,
                authority=f"https://login.microsoftonline.com/{settings.ms_tenant_id}",
                client_credential=settings.ms_client_secret,
            )

            # Try silent token acquisition first (from cache)
            accounts = self._msal_app.get_accounts()
            result = None
            if accounts:
                result = self._msal_app.acquire_token_silent(self.SCOPES, account=accounts[0])

            if not result:
                # In production, redirect user to auth flow
                # For now, use client credentials or pre-stored refresh token
                result = self._msal_app.acquire_token_for_client(
                    scopes=["https://graph.microsoft.com/.default"]
                )

            if "access_token" in result:
                self._access_token = result["access_token"]
                return True
            else:
                print(f"[Outlook] Auth failed: {result.get('error_description')}")
                return False

        except Exception as e:
            print(f"[Outlook] Connection error: {e}")
            return False

    async def disconnect(self):
        self._access_token = None

    async def fetch_recent(self, limit: int = 20) -> list[Notification]:
        """Fetch recent inbox emails."""
        if not self._access_token:
            return []

        notifications = []
        try:
            async with httpx.AsyncClient() as client:
                resp = await client.get(
                    f"{self.GRAPH_BASE}/me/mailFolders/inbox/messages",
                    headers={"Authorization": f"Bearer {self._access_token}"},
                    params={
                        "$top": limit,
                        "$orderby": "receivedDateTime desc",
                        "$select": "id,subject,bodyPreview,from,receivedDateTime,isRead,conversationId",
                    },
                )
                resp.raise_for_status()
                data = resp.json()

                for msg in data.get("value", []):
                    notification = self._message_to_notification(msg)
                    notifications.append(notification)

        except Exception as e:
            print(f"[Outlook] Error fetching recent: {e}")

        return notifications

    async def listen(self):
        """Poll for new messages using delta queries for efficiency."""
        while self._running:
            try:
                async with httpx.AsyncClient() as client:
                    if self._delta_link:
                        url = self._delta_link
                        params = {}
                    else:
                        url = f"{self.GRAPH_BASE}/me/mailFolders/inbox/messages/delta"
                        params = {
                            "$select": "id,subject,bodyPreview,from,receivedDateTime,isRead,conversationId",
                        }

                    resp = await client.get(
                        url,
                        headers={"Authorization": f"Bearer {self._access_token}"},
                        params=params,
                    )
                    resp.raise_for_status()
                    data = resp.json()

                    # Process new/changed messages
                    for msg in data.get("value", []):
                        notification = self._message_to_notification(msg)
                        await self.emit_notification(notification)

                    # Store delta link for next poll
                    self._delta_link = data.get("@odata.deltaLink")

            except httpx.HTTPStatusError as e:
                if e.response.status_code == 401:
                    # Token expired, reconnect
                    await self.connect()
                else:
                    raise
            except Exception as e:
                print(f"[Outlook] Polling error: {e}")

            await asyncio.sleep(self._poll_interval)

    async def reply(self, source_id: str, body: str) -> bool:
        """Reply to an email."""
        try:
            async with httpx.AsyncClient() as client:
                resp = await client.post(
                    f"{self.GRAPH_BASE}/me/messages/{source_id}/reply",
                    headers={
                        "Authorization": f"Bearer {self._access_token}",
                        "Content-Type": "application/json",
                    },
                    json={
                        "message": {"body": {"contentType": "Text", "content": body}},
                        "comment": body,
                    },
                )
                resp.raise_for_status()
                return True
        except Exception as e:
            print(f"[Outlook] Reply error: {e}")
            return False

    def _message_to_notification(self, msg: dict) -> Notification:
        """Convert a Graph API message to unified Notification."""
        from_data = msg.get("from", {}).get("emailAddress", {})

        return Notification(
            source=Source.OUTLOOK,
            source_account=self.account,
            source_id=msg["id"],
            notification_type=NotificationType.EMAIL,
            title=msg.get("subject", "(No Subject)"),
            body=msg.get("bodyPreview", ""),
            sender_name=from_data.get("name", from_data.get("address", "Unknown")),
            thread_id=msg.get("conversationId"),
            timestamp=datetime.fromisoformat(
                msg.get("receivedDateTime", datetime.utcnow().isoformat()).replace("Z", "+00:00")
            ),
            raw_payload={"isRead": msg.get("isRead", False)},
        )
