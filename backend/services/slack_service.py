"""
Command Center - Slack Service

Uses Socket Mode for real-time message delivery.
Socket Mode is perfect for desktop apps — it doesn't need a public URL
(unlike webhook mode). Think of it like a phone call vs a letter:
Socket Mode keeps an open line, webhooks wait for deliveries.

Each Slack workspace gets its own SlackService instance.
"""

import asyncio
from datetime import UTC, datetime

from slack_sdk.socket_mode.aiohttp import SocketModeClient
from slack_sdk.socket_mode.request import SocketModeRequest
from slack_sdk.socket_mode.response import SocketModeResponse
from slack_sdk.web.async_client import AsyncWebClient

from models.notification import (
    Notification,
    NotificationType,
    Priority,
    Source,
)
from services.base import BaseService


class SlackService(BaseService):
    """Slack integration for a single workspace using Socket Mode."""

    def __init__(self, workspace_name: str, bot_token: str, app_token: str):
        super().__init__(Source.SLACK, workspace_name)
        self.workspace_name = workspace_name
        self._bot_token = bot_token
        self._app_token = app_token
        self._web_client: AsyncWebClient | None = None
        self._socket_client: SocketModeClient | None = None
        self._user_cache: dict[str, str] = {}  # user_id -> display_name
        self._channel_cache: dict[str, str] = {}  # channel_id -> channel_name

    async def connect(self) -> bool:
        """Set up Slack clients."""
        try:
            self._web_client = AsyncWebClient(token=self._bot_token)
            self._socket_client = SocketModeClient(
                app_token=self._app_token,
                web_client=self._web_client,
            )

            # Test the connection
            auth = await self._web_client.auth_test()
            if auth["ok"]:
                print(f"[Slack] Authenticated as {auth['user']} in {self.workspace_name}")
                return True
            return False

        except Exception as e:
            print(f"[Slack] Connection error for {self.workspace_name}: {e}")
            return False

    async def disconnect(self):
        if self._socket_client:
            await self._socket_client.close()

    async def fetch_recent(self, limit: int = 20) -> list[Notification]:
        """Fetch recent DMs and mentions."""
        if not self._web_client:
            return []

        notifications = []
        try:
            # Get recent DMs (IMs)
            conversations = await self._web_client.conversations_list(types="im,mpim", limit=10)

            for conv in conversations.get("channels", [])[:5]:
                history = await self._web_client.conversations_history(channel=conv["id"], limit=3)
                for msg in history.get("messages", []):
                    if msg.get("subtype") is None:  # Regular messages only
                        notification = await self._message_to_notification(
                            msg, conv["id"], is_dm=True
                        )
                        if notification:
                            notifications.append(notification)

        except Exception as e:
            print(f"[Slack] Error fetching recent for {self.workspace_name}: {e}")

        return notifications[:limit]

    async def listen(self):
        """Listen for real-time events via Socket Mode."""

        async def handle_event(client: SocketModeClient, req: SocketModeRequest):
            """Process incoming Slack events."""
            # Acknowledge the event immediately
            response = SocketModeResponse(envelope_id=req.envelope_id)
            await client.send_socket_mode_response(response)

            if req.type == "events_api":
                event = req.payload.get("event", {})
                event_type = event.get("type")

                # Handle new messages
                if event_type == "message" and not event.get("subtype"):
                    channel_id = event.get("channel")
                    notification = await self._message_to_notification(event, channel_id)
                    if notification:
                        await self.emit_notification(notification)

                # Handle mentions
                elif event_type == "app_mention":
                    channel_id = event.get("channel")
                    notification = await self._message_to_notification(
                        event, channel_id, is_mention=True
                    )
                    if notification:
                        notification.notification_type = NotificationType.MENTION
                        notification.priority = Priority.HIGH
                        await self.emit_notification(notification)

        # Register the handler and start listening
        self._socket_client.socket_mode_request_listeners.append(handle_event)
        await self._socket_client.connect()

        # Keep alive
        while self._running:
            await asyncio.sleep(1)

    async def reply(self, source_id: str, body: str) -> bool:
        """Slack is read-only — replies are disabled for managed accounts."""
        raise NotImplementedError("Slack is configured as read-only")

    async def _resolve_user(self, user_id: str) -> str:
        """Get display name for a user ID (with caching)."""
        if user_id in self._user_cache:
            return self._user_cache[user_id]

        try:
            info = await self._web_client.users_info(user=user_id)
            name = info["user"]["profile"].get("display_name") or info["user"]["real_name"]
            self._user_cache[user_id] = name
            return name
        except Exception:
            return user_id

    async def _resolve_channel(self, channel_id: str) -> str:
        """Get channel name for a channel ID (with caching)."""
        if channel_id in self._channel_cache:
            return self._channel_cache[channel_id]

        try:
            info = await self._web_client.conversations_info(channel=channel_id)
            name = info["channel"].get("name", channel_id)
            self._channel_cache[channel_id] = name
            return name
        except Exception:
            return channel_id

    async def _message_to_notification(
        self, msg: dict, channel_id: str, is_dm: bool = False, is_mention: bool = False
    ) -> Notification | None:
        """Convert a Slack message to unified Notification."""
        try:
            user_id = msg.get("user", "unknown")
            sender_name = await self._resolve_user(user_id)
            channel_name = await self._resolve_channel(channel_id)
            text = msg.get("text", "")

            # Determine notification type
            if is_mention:
                ntype = NotificationType.MENTION
            elif is_dm:
                ntype = NotificationType.MESSAGE
            else:
                ntype = NotificationType.MESSAGE

            ts = msg.get("ts", "")
            thread_ts = msg.get("thread_ts", ts)

            return Notification(
                source=Source.SLACK,
                source_account=self.workspace_name,
                source_id=f"{channel_id}:{thread_ts}",
                notification_type=ntype,
                title=f"{'@mention in' if is_mention else ''} #{channel_name}"
                if not is_dm
                else f"DM from {sender_name}",
                body=text[:500],  # Truncate long messages
                sender_name=sender_name,
                channel_name=channel_name,
                thread_id=thread_ts if thread_ts != ts else None,
                timestamp=datetime.fromtimestamp(float(ts), tz=UTC) if ts else datetime.now(tz=UTC),
                priority=Priority.HIGH if is_mention else Priority.NORMAL,
                is_actionable=False,  # Slack is read-only
                raw_payload={"channel_id": channel_id, "ts": ts},
            )
        except Exception as e:
            print(f"[Slack] Error parsing message: {e}")
            return None
