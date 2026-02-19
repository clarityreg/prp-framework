"""
Command Center - FastAPI Backend

This is the central hub that:
1. Starts all service listeners on boot
2. Provides a WebSocket endpoint for the Svelte frontend
3. Exposes REST APIs for actions (reply, create task, triage)
4. Handles OAuth callback flows for Gmail & Outlook
"""

import asyncio
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import RedirectResponse

from auth.google import build_auth_url, exchange_code, load_tokens, save_tokens
from config import settings
from models.database import init_db, update_triage_status
from models.notification import (
    Notification,
    NotificationAction,
    Source,
    TaskCreate,
    WebSocketMessage,
)
from services.asana_service import AsanaService
from services.gmail_service import GmailService
from services.outlook_service import OutlookService
from services.plane_service import PlaneService
from services.slack_service import SlackService
from ws.manager import ws_manager

# ============================================================
# Service Registry
# ============================================================


class ServiceRegistry:
    """Keeps track of all active service instances."""

    def __init__(self):
        self.services: list = []
        self.gmail_services: list[GmailService] = []
        self.outlook_service: OutlookService | None = None
        self.slack_services: list[SlackService] = []
        self.asana_service: AsanaService | None = None
        self.plane_service: PlaneService | None = None

    async def start_all(self):
        """Initialize and start all configured services."""
        print("=" * 50)
        print("  COMMAND CENTER - Starting Services")
        print("=" * 50)

        # Gmail accounts
        for email in settings.gmail_accounts:
            tokens = await load_tokens(email)
            service = GmailService(email, credentials=tokens)
            self.gmail_services.append(service)
            self.services.append(service)
            await service.start()

        # Outlook
        if settings.ms_client_id:
            self.outlook_service = OutlookService()
            self.services.append(self.outlook_service)
            await self.outlook_service.start()

        # Slack workspaces
        for ws_config in settings.slack_workspaces:
            service = SlackService(
                workspace_name=ws_config["name"],
                bot_token=ws_config["bot_token"],
                app_token=ws_config["app_token"],
            )
            self.slack_services.append(service)
            self.services.append(service)
            await service.start()

        # Asana
        if settings.asana_access_token:
            self.asana_service = AsanaService()
            self.services.append(self.asana_service)
            await self.asana_service.start()

        # Plane
        if settings.plane_api_key:
            self.plane_service = PlaneService()
            self.services.append(self.plane_service)
            await self.plane_service.start()

        print("=" * 50)
        print(f"  {len(self.services)} services initialized")
        print("=" * 50)

    async def stop_all(self):
        """Stop all services gracefully."""
        for service in self.services:
            await service.stop()

    async def fetch_all_recent(self, limit: int = 50) -> list[Notification]:
        """Fetch recent notifications from all services."""
        all_notifications = []
        tasks = [s.fetch_recent(limit=10) for s in self.services]
        results = await asyncio.gather(*tasks, return_exceptions=True)

        for result in results:
            if isinstance(result, list):
                all_notifications.extend(result)
            elif isinstance(result, Exception):
                print(f"Error fetching recent: {result}")

        # Sort by timestamp, newest first
        all_notifications.sort(key=lambda n: n.timestamp, reverse=True)
        return all_notifications[:limit]

    def get_service_for_reply(self, source: Source, account: str):
        """Find the right service instance to handle a reply."""
        if source == Source.GMAIL:
            return next((s for s in self.gmail_services if s.email == account), None)
        elif source == Source.OUTLOOK:
            return self.outlook_service
        elif source == Source.SLACK:
            return next((s for s in self.slack_services if s.workspace_name == account), None)
        return None


registry = ServiceRegistry()


# ============================================================
# FastAPI App
# ============================================================


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Startup and shutdown logic."""
    # Startup
    await init_db()
    await registry.start_all()
    yield
    # Shutdown
    await registry.stop_all()


app = FastAPI(
    title="Command Center Backend",
    version="0.1.0",
    lifespan=lifespan,
)

# CORS — allow Tauri/Vite dev server
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:1420", "tauri://localhost", "https://tauri.localhost"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ============================================================
# WebSocket Endpoint
# ============================================================


@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    """Main WebSocket connection for the frontend."""
    await ws_manager.connect(websocket)

    try:
        # Send initial load of recent notifications
        recent = await registry.fetch_all_recent(limit=50)
        initial_msg = WebSocketMessage(
            event="initial_load",
            data={"notifications": [n.model_dump(mode="json") for n in recent]},
        )
        await websocket.send_text(initial_msg.model_dump_json())

        # Keep connection alive and handle incoming messages
        while True:
            data = await websocket.receive_text()
            # Handle any frontend-to-backend messages here
            print(f"[WS] Received from frontend: {data}")

    except WebSocketDisconnect:
        ws_manager.disconnect(websocket)
    except Exception as e:
        print(f"[WS] Error: {e}")
        ws_manager.disconnect(websocket)


# ============================================================
# REST API Endpoints
# ============================================================


@app.get("/api/health")
async def health_check():
    """Health check endpoint."""
    return {
        "status": "ok",
        "services": len(registry.services),
        "ws_connections": len(ws_manager.active_connections),
    }


@app.get("/api/notifications")
async def get_notifications(limit: int = 50, status: str | None = None):
    """Fetch notifications (REST fallback for initial load)."""
    notifications = await registry.fetch_all_recent(limit=limit)
    if status:
        notifications = [n for n in notifications if n.triage_status.value == status]
    return {"notifications": [n.model_dump(mode="json") for n in notifications]}


@app.post("/api/notifications/{notification_id}/action")
async def action_notification(notification_id: str, action: NotificationAction):
    """Perform an action on a notification (reply, archive, snooze, etc.)."""

    if action.action == "reply":
        # Find the right service and reply
        payload = action.payload or {}
        body = payload.get("body", "")
        source = payload.get("source")
        account = payload.get("source_account")

        if not source or not body or not account:
            raise HTTPException(
                400, "Reply requires 'source', 'source_account', and 'body' in payload"
            )

        try:
            source_enum = Source(source)
        except ValueError as err:
            raise HTTPException(400, f"Invalid source: {source}") from err
        service = registry.get_service_for_reply(source_enum, account)
        if not service:
            raise HTTPException(404, f"No service found for {source}:{account}")

        success = await service.reply(payload.get("source_id", notification_id), body)
        if not success:
            raise HTTPException(500, "Reply failed")

        return {"status": "replied"}

    elif action.action == "archive":
        updated = await update_triage_status(notification_id, "archived")
        if not updated:
            raise HTTPException(404, f"Notification {notification_id} not found")
        await ws_manager.send_update(notification_id, {"triage_status": "archived"})
        return {"status": "archived"}

    elif action.action == "mark_read":
        updated = await update_triage_status(notification_id, "read")
        if not updated:
            raise HTTPException(404, f"Notification {notification_id} not found")
        await ws_manager.send_update(notification_id, {"triage_status": "read"})
        return {"status": "read"}

    elif action.action == "snooze":
        from datetime import UTC, datetime, timedelta

        minutes = (action.payload or {}).get("snooze_minutes", 30)
        snoozed_until = datetime.now(UTC) + timedelta(minutes=minutes)
        updated = await update_triage_status(
            notification_id, "snoozed", snoozed_until=snoozed_until
        )
        if not updated:
            raise HTTPException(404, f"Notification {notification_id} not found")
        await ws_manager.send_update(
            notification_id,
            {
                "triage_status": "snoozed",
                "snooze_minutes": minutes,
            },
        )
        return {"status": "snoozed", "minutes": minutes}

    else:
        raise HTTPException(400, f"Unknown action: {action.action}")


@app.post("/api/tasks")
async def create_task(task: TaskCreate):
    """Create a task in Plane or Asana."""

    if task.target == "plane" and registry.plane_service:
        result = await registry.plane_service.create_issue(
            title=task.title,
            description=task.description or "",
            priority=task.priority.value,
            project_id=task.project_id,
        )
        if result:
            return {"status": "created", "target": "plane", "issue": result}
        raise HTTPException(500, "Failed to create Plane issue")

    elif task.target == "asana" and registry.asana_service:
        result = await registry.asana_service.create_task(
            title=task.title,
            description=task.description or "",
            project_gid=task.project_id,
        )
        if result:
            return {"status": "created", "target": "asana", "task": result}
        raise HTTPException(500, "Failed to create Asana task")

    else:
        raise HTTPException(400, f"Target '{task.target}' is not configured")


@app.get("/api/services/status")
async def services_status():
    """Get the connection status of all services."""
    return {
        "services": [
            {
                "service": s.source.value,
                "connected": s._running,
                "account": s.account,
            }
            for s in registry.services
        ]
    }


@app.get("/api/auth/status")
async def auth_status():
    """Check which Gmail accounts need OAuth setup."""
    accounts = []
    for svc in registry.gmail_services:
        has_tokens = svc._credentials is not None
        accounts.append(
            {
                "email": svc.email,
                "connected": svc._running and has_tokens,
                "needs_auth": not has_tokens,
                "auth_url": f"/auth/google/start?email={svc.email}" if not has_tokens else None,
            }
        )
    return {"gmail_accounts": accounts}


# ============================================================
# OAuth Callback Routes (for Gmail & Outlook setup)
# ============================================================


@app.get("/auth/google/start")
async def google_oauth_start(email: str):
    """Redirect user to Google consent screen for the given email."""
    if not settings.google_client_id or not settings.google_client_secret:
        raise HTTPException(500, "Google OAuth not configured (missing client_id/secret)")
    auth_url = build_auth_url(email)
    return RedirectResponse(url=auth_url)


@app.get("/auth/google/callback")
async def google_oauth_callback(code: str, state: str = ""):
    """Handle Google OAuth callback — exchange code for tokens and store them."""
    email = state
    if not email:
        raise HTTPException(400, "Missing state parameter (email)")

    try:
        tokens = await exchange_code(code)
        await save_tokens(email, tokens)
        print(f"[OAuth] Tokens saved for {email}")

        # Reconnect the Gmail service with the new tokens
        for svc in registry.gmail_services:
            if svc.email == email:
                svc._credentials = tokens
                await svc.stop()
                await svc.start()
                break

        return {
            "status": "success",
            "message": f"Gmail connected for {email}",
            "email": email,
        }
    except Exception as e:
        print(f"[OAuth] Error exchanging code for {email}: {e}")
        raise HTTPException(500, f"OAuth token exchange failed: {e}") from e


@app.get("/auth/microsoft/callback")
async def microsoft_oauth_callback(code: str, state: str = ""):
    """Handle Microsoft OAuth callback after user authorizes."""
    return {"status": "Microsoft OAuth callback received", "code": code[:10] + "..."}
