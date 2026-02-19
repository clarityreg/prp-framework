"""
Command Center - Gmail Service

Connects to Gmail via the Google API.
Uses historyId-based incremental sync for efficient polling.
Each Gmail account gets its own GmailService instance.
"""

import asyncio
import base64
import contextlib
from datetime import UTC, datetime
from email.utils import parsedate_to_datetime

from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from googleapiclient.discovery import build

from config import settings
from models.notification import (
    Notification,
    NotificationType,
    Source,
)
from services.base import BaseService


class GmailService(BaseService):
    """Gmail integration for a single account."""

    def __init__(self, account_email: str, credentials: dict | None = None):
        super().__init__(Source.GMAIL, account_email)
        self.email = account_email
        self._credentials = credentials
        self._gmail_client = None
        self._last_history_id: str | None = None
        self._seen_ids: set[str] = set()
        self._poll_interval = 30  # seconds

    async def connect(self) -> bool:
        """Set up Gmail API client with stored credentials."""
        try:
            if not self._credentials:
                from auth.google import load_tokens

                self._credentials = await load_tokens(self.email)

            if not self._credentials:
                print(f"[Gmail] No credentials for {self.email} - needs OAuth setup")
                print(f"[Gmail] Visit /auth/google/start?email={self.email} to authorize")
                return False

            creds = Credentials(
                token=self._credentials.get("access_token"),
                refresh_token=self._credentials.get("refresh_token"),
                token_uri="https://oauth2.googleapis.com/token",
                client_id=settings.google_client_id,
                client_secret=settings.google_client_secret,
            )

            if creds.expired and creds.refresh_token:
                creds.refresh(Request())
                from auth.google import save_tokens

                await save_tokens(
                    self.email,
                    {
                        "access_token": creds.token,
                        "refresh_token": creds.refresh_token,
                        "expires_at": creds.expiry.isoformat() if creds.expiry else None,
                    },
                )

            self._gmail_client = build("gmail", "v1", credentials=creds)
            print(f"[Gmail] Connected for {self.email}")
            return True
        except Exception as e:
            print(f"[Gmail] Connection error for {self.email}: {e}")
            return False

    async def disconnect(self):
        self._gmail_client = None

    async def fetch_recent(self, limit: int = 20) -> list[Notification]:
        """Fetch the most recent emails and seed the historyId for incremental sync."""
        if not self._gmail_client:
            return []

        notifications = []
        try:
            results = await asyncio.get_event_loop().run_in_executor(
                None,
                lambda: (
                    self._gmail_client.users()
                    .messages()
                    .list(userId="me", maxResults=limit, q="is:inbox")
                    .execute()
                ),
            )

            messages = results.get("messages", [])
            for msg_ref in messages:
                msg_id = msg_ref["id"]
                self._seen_ids.add(msg_id)
                notification = await self._message_to_notification(msg_id)
                if notification:
                    notifications.append(notification)

            # Seed the historyId from the profile for subsequent incremental polling
            if not self._last_history_id:
                profile = await asyncio.get_event_loop().run_in_executor(
                    None,
                    lambda: self._gmail_client.users().getProfile(userId="me").execute(),
                )
                self._last_history_id = str(profile.get("historyId", ""))

        except Exception as e:
            print(f"[Gmail] Error fetching recent for {self.email}: {e}")

        return notifications

    async def listen(self):
        """Poll for new emails using historyId-based incremental sync."""
        while self._running:
            try:
                if self._last_history_id:
                    await self._poll_incremental()
                else:
                    # Fallback: no historyId yet, do a full unread query
                    await self._poll_full()
            except Exception as e:
                print(f"[Gmail] Polling error for {self.email}: {e}")

            await asyncio.sleep(self._poll_interval)

    async def _poll_incremental(self):
        """Use history.list to get only new messages since last check."""
        try:
            history_id = self._last_history_id
            results = await asyncio.get_event_loop().run_in_executor(
                None,
                lambda: (
                    self._gmail_client.users()
                    .history()
                    .list(
                        userId="me",
                        startHistoryId=history_id,
                        historyTypes=["messageAdded"],
                    )
                    .execute()
                ),
            )

            # Update historyId regardless of whether there are new messages
            new_history_id = results.get("historyId")
            if new_history_id:
                self._last_history_id = str(new_history_id)

            histories = results.get("history", [])
            new_count = 0
            for record in histories:
                for added in record.get("messagesAdded", []):
                    msg_id = added["message"]["id"]
                    labels = added["message"].get("labelIds", [])

                    # Only process inbox messages we haven't seen
                    if msg_id not in self._seen_ids and "INBOX" in labels:
                        self._seen_ids.add(msg_id)
                        notification = await self._message_to_notification(msg_id)
                        if notification:
                            await self.emit_notification(notification)
                            new_count += 1

            if new_count:
                print(f"[Gmail] {self.email}: {new_count} new message(s)")

        except Exception as e:
            error_str = str(e)
            if "404" in error_str or "historyId" in error_str.lower():
                # historyId expired or invalid — reset and do full poll next cycle
                print(f"[Gmail] historyId expired for {self.email}, resetting")
                self._last_history_id = None
            else:
                raise

    async def _poll_full(self):
        """Fallback polling: query unread inbox messages."""
        results = await asyncio.get_event_loop().run_in_executor(
            None,
            lambda: (
                self._gmail_client.users()
                .messages()
                .list(userId="me", maxResults=10, q="is:inbox is:unread")
                .execute()
            ),
        )

        messages = results.get("messages", [])
        for msg_ref in messages:
            msg_id = msg_ref["id"]
            if msg_id not in self._seen_ids:
                self._seen_ids.add(msg_id)
                notification = await self._message_to_notification(msg_id)
                if notification:
                    await self.emit_notification(notification)

        # Seed historyId for next cycle
        profile = await asyncio.get_event_loop().run_in_executor(
            None,
            lambda: self._gmail_client.users().getProfile(userId="me").execute(),
        )
        self._last_history_id = str(profile.get("historyId", ""))

    async def reply(self, source_id: str, body: str) -> bool:
        """Reply to an email by message ID."""
        try:
            original = await asyncio.get_event_loop().run_in_executor(
                None,
                lambda: (
                    self._gmail_client.users()
                    .messages()
                    .get(
                        userId="me",
                        id=source_id,
                        format="metadata",
                        metadataHeaders=["Subject", "From", "To", "Message-ID"],
                    )
                    .execute()
                ),
            )

            headers = {
                h["name"]: h["value"] for h in original.get("payload", {}).get("headers", [])
            }
            thread_id = original.get("threadId")

            reply_to = headers.get("From", "")
            subject = headers.get("Subject", "")
            if not subject.startswith("Re: "):
                subject = f"Re: {subject}"

            message_body = (
                f"To: {reply_to}\r\n"
                f"Subject: {subject}\r\n"
                f"In-Reply-To: {headers.get('Message-ID', '')}\r\n"
                f"\r\n"
                f"{body}"
            )

            encoded = base64.urlsafe_b64encode(message_body.encode()).decode()

            await asyncio.get_event_loop().run_in_executor(
                None,
                lambda: (
                    self._gmail_client.users()
                    .messages()
                    .send(userId="me", body={"raw": encoded, "threadId": thread_id})
                    .execute()
                ),
            )
            return True

        except Exception as e:
            print(f"[Gmail] Reply error: {e}")
            return False

    async def _message_to_notification(self, message_id: str) -> Notification | None:
        """Convert a Gmail message to our unified Notification format."""
        try:
            msg = await asyncio.get_event_loop().run_in_executor(
                None,
                lambda: (
                    self._gmail_client.users()
                    .messages()
                    .get(
                        userId="me",
                        id=message_id,
                        format="metadata",
                        metadataHeaders=["Subject", "From", "Date"],
                    )
                    .execute()
                ),
            )

            headers = {h["name"]: h["value"] for h in msg.get("payload", {}).get("headers", [])}
            snippet = msg.get("snippet", "")

            # Parse sender
            from_header = headers.get("From", "Unknown")
            sender_name = from_header.split("<")[0].strip().strip('"')

            # Parse Date header properly
            timestamp = datetime.now(tz=UTC)
            date_str = headers.get("Date")
            if date_str:
                with contextlib.suppress(ValueError, TypeError):
                    timestamp = parsedate_to_datetime(date_str)

            return Notification(
                source=Source.GMAIL,
                source_account=self.email,
                source_id=message_id,
                notification_type=NotificationType.EMAIL,
                title=headers.get("Subject", "(No Subject)"),
                body=snippet,
                sender_name=sender_name,
                thread_id=msg.get("threadId"),
                timestamp=timestamp,
                raw_payload={"labels": msg.get("labelIds", [])},
            )
        except Exception as e:
            print(f"[Gmail] Error parsing message {message_id}: {e}")
            return None
