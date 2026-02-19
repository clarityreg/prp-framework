"""
Command Center - WebSocket Manager

This is the single pipe that connects all your services to the frontend.
Think of it like a funnel: Gmail, Slack, Outlook, etc. all pour notifications in,
and they flow out through one WebSocket to your Svelte UI.
"""

import asyncio

from fastapi import WebSocket

from models.notification import Notification, WebSocketMessage


class ConnectionManager:
    """Manages WebSocket connections to the frontend."""

    def __init__(self):
        self.active_connections: set[WebSocket] = set()
        self._queue: asyncio.Queue = asyncio.Queue()

    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.add(websocket)
        print(f"[WS] Frontend connected. Active connections: {len(self.active_connections)}")

    def disconnect(self, websocket: WebSocket):
        self.active_connections.discard(websocket)
        print(f"[WS] Frontend disconnected. Active connections: {len(self.active_connections)}")

    async def broadcast(self, message: WebSocketMessage):
        """Send a message to all connected frontends."""
        data = message.model_dump_json()
        dead_connections = set()

        for connection in self.active_connections:
            try:
                await connection.send_text(data)
            except Exception:
                dead_connections.add(connection)

        # Clean up dead connections
        self.active_connections -= dead_connections

    async def send_notification(self, notification: Notification):
        """Convenience: wrap a notification in a WebSocketMessage and broadcast it."""
        msg = WebSocketMessage(
            event="new_notification",
            data=notification.model_dump(mode="json"),
        )
        await self.broadcast(msg)

    async def send_update(self, notification_id: str, updates: dict):
        """Send a notification update (e.g. status change)."""
        msg = WebSocketMessage(
            event="notification_updated",
            data={"id": notification_id, **updates},
        )
        await self.broadcast(msg)

    async def send_connection_status(self, service: str, connected: bool, account: str = ""):
        """Tell the frontend about service connection status."""
        msg = WebSocketMessage(
            event="connection_status",
            data={
                "service": service,
                "connected": connected,
                "account": account,
            },
        )
        await self.broadcast(msg)


# Singleton instance
ws_manager = ConnectionManager()
