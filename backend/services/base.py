"""
Command Center - Base Service

Every service (Gmail, Slack, etc.) inherits from this.
Think of it like a power adapter: each country (service) has a different plug,
but they all need to output the same voltage (Notification format).
"""

import asyncio
import contextlib
from abc import ABC, abstractmethod

from models.database import save_notification
from models.notification import Notification, Source
from ws.manager import ws_manager


class BaseService(ABC):
    """Abstract base for all service integrations."""

    def __init__(self, source: Source, account: str):
        self.source = source
        self.account = account
        self._running = False
        self._task: asyncio.Task | None = None

    @abstractmethod
    async def connect(self) -> bool:
        """Establish connection to the service. Return True if successful."""
        pass

    @abstractmethod
    async def disconnect(self):
        """Clean up connections."""
        pass

    @abstractmethod
    async def fetch_recent(self, limit: int = 20) -> list[Notification]:
        """Fetch recent items for initial load."""
        pass

    @abstractmethod
    async def listen(self):
        """Start listening for real-time updates. Runs as a background task."""
        pass

    async def reply(self, source_id: str, body: str) -> bool:
        """Reply to a message/email. Override in services that support it."""
        raise NotImplementedError(f"{self.source.value} does not support replies")

    async def start(self):
        """Start the service listener as a background task."""
        connected = await self.connect()
        if connected:
            self._running = True
            self._task = asyncio.create_task(self._run_listener())
            await ws_manager.send_connection_status(self.source.value, True, self.account)
            print(f"[{self.source.value}] ✓ Connected: {self.account}")
        else:
            await ws_manager.send_connection_status(self.source.value, False, self.account)
            print(f"[{self.source.value}] ✗ Failed to connect: {self.account}")

    async def stop(self):
        """Stop the service listener."""
        self._running = False
        if self._task:
            self._task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await self._task
        await self.disconnect()
        await ws_manager.send_connection_status(self.source.value, False, self.account)

    async def _run_listener(self):
        """Run the listener with auto-reconnect."""
        while self._running:
            try:
                await self.listen()
            except asyncio.CancelledError:
                break
            except Exception as e:
                print(f"[{self.source.value}] Error in listener ({self.account}): {e}")
                await ws_manager.send_connection_status(self.source.value, False, self.account)
                # Wait before reconnecting
                await asyncio.sleep(5)
                if self._running:
                    print(f"[{self.source.value}] Reconnecting {self.account}...")
                    await self.connect()

    async def emit_notification(self, notification: Notification):
        """Persist a notification to the database, then broadcast to the frontend."""
        await save_notification(notification)
        await ws_manager.send_notification(notification)
