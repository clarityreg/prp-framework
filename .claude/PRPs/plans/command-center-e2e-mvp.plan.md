# Implementation Plan: Command Center End-to-End MVP

**Created**: 2026-02-19
**Status**: Ready for Implementation
**Archon Project ID**: a31dcd2a-d8c1-487e-bdc4-fef157034d2f

---

## Overview

Get the Command Center desktop app fully running end-to-end: Tauri launches, spawns the Python FastAPI backend as a sidecar, the SvelteKit frontend connects via WebSocket, and real notifications from Gmail and Slack flow into the unified inbox. The user can view, triage, and archive notifications from a single dark-themed desktop window. Gmail supports full reply. Slack is read-only (some accounts are managed externally and reply is not appropriate); mark-as-read on Slack is a nice-to-have but not required.

## Tooling Decisions

- **Python package management**: [uv](https://docs.astral.sh/uv/) - fast, Rust-based pip/venv replacement
- **Python linting & formatting**: [Ruff](https://docs.astral.sh/ruff/) - replaces flake8, black, isort in one tool
- **Slack integration**: Read-only (no reply). Mark-as-read is nice-to-have, not essential
- **Security scanning**: [Trivy](https://trivy.dev/) - secret detection, dependency vulnerability scanning, misconfiguration checks

## User Stories

- As a user, I want to launch one app and see all my Gmail and Slack notifications in one place
- As a user, I want to reply to Gmail emails without leaving the app
- As a user, I want to read Slack messages from multiple workspaces (read-only, some accounts are externally managed)
- As a user, I want to archive, snooze, and triage notifications with keyboard shortcuts
- As a user, I want the app to reconnect automatically if the backend restarts

## Success Criteria

- [ ] `npm run tauri dev` launches the full app (frontend + backend)
- [ ] Gmail OAuth flow completes and stores tokens
- [ ] Slack Socket Mode connects and receives real-time messages
- [ ] Notifications appear in the inbox within 5 seconds of arrival
- [ ] Reply works for Gmail
- [ ] Slack notifications display correctly (read-only)
- [ ] Ruff lint passes with zero errors
- [ ] Archive, snooze, and mark-read persist across restarts
- [ ] App window renders correctly at 1200x800

---

## Mandatory Reading

Before implementation, read these files to understand patterns:

| File | Purpose | Key Lines |
|------|---------|-----------|
| `backend/main.py` | Service registry, endpoints, WS handler | All |
| `backend/services/base.py` | BaseService abstract class (all services inherit) | All |
| `backend/services/gmail_service.py` | Gmail integration pattern | `connect()`, `listen()`, `_message_to_notification()` |
| `backend/services/slack_service.py` | Slack Socket Mode pattern | `connect()`, `listen()`, `handle_event()` |
| `backend/config.py` | Environment variable structure | `Settings` class |
| `backend/models/notification.py` | Unified notification model | All enums + `Notification` class |
| `backend/models/database.py` | SQLAlchemy async models | `NotificationRecord`, `TokenStore` |
| `src/lib/ws.ts` | WebSocket client with reconnection | `handleMessage()` |
| `src/lib/stores/index.ts` | Svelte store patterns | `createNotificationStore()` |
| `src-tauri/tauri.conf.json` | Tauri window + sidecar config | `plugins.shell` |
| `src-tauri/src/main.rs` | Rust entry point | `setup` closure |

## Patterns to Follow

### Naming
- Backend services: `{service}_service.py` in `backend/services/`
- Models: Pydantic for API, SQLAlchemy for DB in `backend/models/`
- Frontend components: PascalCase `.svelte` in `src/lib/components/`
- Stores: camelCase exports in `src/lib/stores/index.ts`

### Code Style
- Python: async/await throughout, Pydantic models for all data shapes
- Python linting/formatting: **Ruff** (replaces flake8, black, isort)
- Python packages: **uv** (replaces pip, venv, pip-compile)
- TypeScript: strict types mirroring Python models
- Svelte: reactive `$store` syntax, event handlers via `on:click`

### Error Handling
- Backend: `try/except` with `print()` logging per service
- Frontend: WebSocket auto-reconnect with exponential backoff
- Services: `BaseService._run_listener()` catches exceptions and auto-reconnects after 5s

### Testing
- No test infrastructure exists yet - will be set up in Phase 3

---

## Implementation Tasks

### Phase 1: Foundation - Project Setup & Dependencies

#### Task 1.1: Install Node.js Dependencies and Verify SvelteKit Builds
**Status**: todo
**Feature**: foundation

**Description**: Run `npm install` to install all frontend dependencies. Verify that `npm run dev` starts the Vite dev server on port 1420 and serves the SvelteKit app. Fix any dependency resolution issues.

**Files**:
- Read: `package.json`
- Possibly modify: `package.json` (if version conflicts)

**Validation**:
```bash
npm install && npm run build
```

**Acceptance Criteria**:
- [ ] `npm install` completes without errors
- [ ] `npm run build` produces output in `build/` directory
- [ ] `npm run dev` serves on http://localhost:1420

---

#### Task 1.2: Set Up Python Environment with uv and Install Backend Dependencies
**Status**: todo
**Feature**: foundation

**Description**: Use **uv** (Astral's Rust-based Python package manager) to manage the backend environment. Initialize a uv project in `backend/`, migrate from `requirements.txt` to `pyproject.toml`, and install all dependencies. Also add **Ruff** as a dev dependency for linting and formatting. Verify FastAPI starts on port 8766. The backend should start even if no service credentials are configured (services will just report as disconnected).

**Steps**:
1. `cd backend && uv init` (or create `pyproject.toml` manually)
2. `uv add` all production dependencies from `requirements.txt`
3. `uv add --dev ruff` for linting/formatting
4. Configure Ruff in `pyproject.toml` (line length, target Python version, select rules)
5. Run `uv run ruff check .` and `uv run ruff format .` to baseline the codebase
6. Verify `uv run uvicorn main:app --port 8766` starts

**Files**:
- Create: `backend/pyproject.toml` (replaces `requirements.txt`)
- Delete or keep: `backend/requirements.txt` (can keep as reference, uv uses pyproject.toml)
- Create: `backend/.env` (from template)

**Validation**:
```bash
cd backend && uv sync
uv run ruff check .
uv run ruff format --check .
uv run uvicorn main:app --port 8766
# Should start, hit http://127.0.0.1:8766/api/health
```

**Acceptance Criteria**:
- [ ] `uv sync` installs all dependencies into `.venv/`
- [ ] `pyproject.toml` has all dependencies (production + dev)
- [ ] Ruff config present in `pyproject.toml` with sensible defaults
- [ ] `ruff check .` passes with zero errors
- [ ] `ruff format --check .` passes (code is formatted)
- [ ] `uv run uvicorn main:app --port 8766` starts without import errors
- [ ] `/api/health` returns `{"status": "ok"}`

---

#### Task 1.3: Verify Tauri Rust Shell Compiles
**Status**: todo
**Feature**: foundation

**Description**: Ensure the Tauri Rust project compiles. Install Rust toolchain if needed. The `src-tauri/` directory has Cargo.toml with `tauri 2`, `tauri-plugin-shell 2`, and `tauri-plugin-notification 2`. Run `cargo check` to verify dependencies resolve.

**Files**:
- Read: `src-tauri/Cargo.toml`, `src-tauri/src/main.rs`

**Validation**:
```bash
cd src-tauri && cargo check
```

**Acceptance Criteria**:
- [ ] `cargo check` completes without errors
- [ ] All Tauri 2.x plugin dependencies resolve

---

#### Task 1.4: Create .env Template with All Configuration Variables
**Status**: todo
**Feature**: foundation

**Description**: Create a `.env.example` file documenting every environment variable from `backend/config.py`. Include comments explaining each variable, which are required vs optional, and links to where to get credentials. Create user's `.env` from this template.

**Files**:
- Create: `backend/.env.example`
- Create: `backend/.env` (user fills in)

**Acceptance Criteria**:
- [ ] `.env.example` documents all variables from `Settings` class
- [ ] Variables are grouped by service (Google, Microsoft, Slack, Asana, Plane)
- [ ] Comments indicate which are required for MVP (Gmail + Slack only)

---

### Phase 2: Backend - Wire Up Gmail & Slack

#### Task 2.1: Implement Complete Gmail OAuth Flow
**Status**: todo
**Feature**: gmail

**Description**: The current `GmailService.connect()` expects pre-loaded credentials but the OAuth flow stubs in `main.py` don't actually exchange codes for tokens or store them. Implement:

1. A proper OAuth initiation endpoint (`GET /auth/google/start`) that redirects to Google's consent screen
2. Complete the `GET /auth/google/callback` to exchange the auth code for tokens
3. Store tokens in the `TokenStore` database table
4. Load tokens from `TokenStore` when `GmailService` starts
5. Token refresh logic (already partially in `GmailService.connect()`)

**Key Pattern**: Google OAuth 2.0 with offline access for refresh tokens. The redirect URI is `http://localhost:8766/auth/google/callback` (already in config).

**Files**:
- Modify: `backend/main.py` - add `/auth/google/start` endpoint, complete callback
- Modify: `backend/services/gmail_service.py` - load tokens from DB in `connect()`
- Modify: `backend/models/database.py` - ensure `TokenStore` CRUD helpers exist
- Possibly create: `backend/auth/google.py` - OAuth helper functions

**Validation**:
```bash
# Start backend, navigate to http://localhost:8766/auth/google/start
# Complete Google consent, verify token stored in DB
# Restart backend, verify Gmail service auto-connects using stored token
```

**Acceptance Criteria**:
- [ ] `/auth/google/start` redirects to Google consent screen
- [ ] Callback exchanges code for access + refresh tokens
- [ ] Tokens stored in `TokenStore` table (encrypted in production)
- [ ] `GmailService` loads tokens from DB on startup
- [ ] Token refresh works when access token expires

---

#### Task 2.2: Fix Gmail Polling and Notification Deduplication
**Status**: todo
**Feature**: gmail

**Description**: The current `GmailService.listen()` polls every 30 seconds but doesn't track which messages it has already sent to the frontend, leading to duplicate notifications. Fix by:

1. Track `_seen_message_ids` set in `GmailService`
2. Use Gmail's `historyId` for incremental sync (more efficient than re-listing)
3. Parse the `Date` header properly instead of using `datetime.utcnow()`
4. Store fetched notifications in the `NotificationRecord` database table

**Files**:
- Modify: `backend/services/gmail_service.py` - dedup logic, history-based sync
- Modify: `backend/models/database.py` - add notification CRUD helpers

**Acceptance Criteria**:
- [ ] No duplicate notifications sent to frontend
- [ ] History-based incremental sync reduces API calls
- [ ] Timestamps accurately reflect email send time
- [ ] Notifications persist in SQLite across restarts

---

#### Task 2.3: Verify and Fix Slack Socket Mode Connection (Read-Only)
**Status**: todo
**Feature**: slack

**Description**: The `SlackService` implementation needs real-world testing. Slack is **read-only** for this MVP - some accounts are externally managed and reply is not appropriate. Mark-as-read via Slack API (`conversations.mark`) is a nice-to-have but not essential.

**Verify**:
1. Socket Mode connects with a valid `app_token` (xapp-...) and `bot_token` (xoxb-...)
2. Event subscriptions are configured in the Slack app (message.im, message.channels, app_mention)
3. The `handle_event` closure correctly processes real message payloads
4. User and channel name resolution works via the cache

**Modify for read-only**:
5. Remove or disable the `reply()` method in `SlackService` (keep it as a no-op that returns `False`)
6. Hide the reply textarea in `DetailPanel.svelte` when source is Slack
7. (Nice-to-have) Add `mark_read()` method using `conversations.mark` API to mark Slack messages as read

**Files**:
- Modify: `backend/services/slack_service.py` - disable reply, optionally add mark_read
- Modify: `src/lib/components/DetailPanel.svelte` - hide reply section for Slack
- Read: `backend/config.py` - verify env var names match Slack app config

**Validation**:
```bash
# Start backend with valid Slack tokens in .env
# Send a DM to the bot in Slack
# Verify notification appears in frontend
# Verify reply section is hidden for Slack notifications
```

**Acceptance Criteria**:
- [ ] Socket Mode connects and stays connected
- [ ] DMs trigger `new_notification` events
- [ ] @mentions trigger high-priority notifications
- [ ] Channel names and user names resolve correctly
- [ ] Reply UI is hidden for Slack source notifications
- [ ] (Nice-to-have) Mark-as-read updates Slack read cursor

---

#### Task 2.4: Add Database Persistence for Notifications and Triage State
**Status**: todo
**Feature**: persistence

**Description**: Currently, notifications only live in memory and disappear on restart. Wire up the `NotificationRecord` SQLAlchemy model:

1. Save every incoming notification to the DB via `emit_notification()`
2. Load notifications from DB on startup (not just from live service fetch)
3. Persist triage actions (archive, mark_read, snooze) to the DB
4. On WebSocket `initial_load`, merge DB records with live fetches
5. Add `snoozed_until` handling - unsnoozed items reappear when their time is up

**Files**:
- Modify: `backend/services/base.py` - save to DB in `emit_notification()`
- Modify: `backend/main.py` - load from DB in `websocket_endpoint`, persist actions
- Modify: `backend/models/database.py` - add async CRUD functions

**Acceptance Criteria**:
- [ ] Notifications survive backend restarts
- [ ] Triage actions (archive, read, snooze) persist
- [ ] Snoozed notifications reappear after their timer expires
- [ ] Initial load merges stored + fresh notifications without duplicates

---

### Phase 3: Tauri Shell - Desktop Integration

#### Task 3.1: Configure Tauri to Spawn Python Backend as Sidecar
**Status**: todo
**Feature**: tauri

**Description**: Currently `main.rs` just prints a startup message and the Python backend is launched separately via `npm run backend`. For a real desktop app, Tauri must spawn the Python process via `uv run`:

1. Use `tauri-plugin-shell` to spawn `uv run uvicorn main:app --host 127.0.0.1 --port 8766` as a sidecar (uv handles venv activation automatically)
2. Set the working directory to `backend/` (or adjust imports)
3. Wait for the backend to be ready before the frontend connects (health check polling)
4. Kill the Python process when the Tauri app closes

**Key Decision**: For dev, use `Command::new_sidecar()` with the shell plugin. `uv run` handles venv resolution automatically - no manual venv activation needed. For production builds, bundle the Python backend (or use PyInstaller/Nuitka to create a standalone binary).

**Files**:
- Modify: `src-tauri/src/main.rs` - spawn python in `setup()`, kill on exit
- Modify: `src-tauri/tauri.conf.json` - sidecar configuration
- Modify: `src/lib/ws.ts` - add startup health-check polling before WS connect
- Possibly modify: `package.json` - adjust `dev:all` script

**Acceptance Criteria**:
- [ ] `npm run tauri dev` starts both frontend and backend
- [ ] Python process starts before WebSocket connection attempt
- [ ] Frontend waits for backend health check before connecting WS
- [ ] Python process is killed when app window closes
- [ ] No orphan Python processes after app exit

---

#### Task 3.2: Add Frontend Backend-Ready Detection
**Status**: todo
**Feature**: tauri

**Description**: The frontend currently connects to WebSocket immediately on mount (`+layout.svelte`). When Tauri spawns the backend, there's a startup delay. Add a "waiting for backend" state:

1. On mount, poll `http://127.0.0.1:8766/api/health` every 500ms
2. Show a loading/splash screen while waiting
3. Once health check succeeds, connect WebSocket
4. If health check fails after 30 seconds, show error state with retry button

**Files**:
- Modify: `src/routes/+layout.svelte` - add health check polling before WS connect
- Modify: `src/lib/ws.ts` - export a `waitForBackend()` function
- Add splash/loading CSS to `+layout.svelte`

**Acceptance Criteria**:
- [ ] App shows loading state while backend starts
- [ ] WebSocket connects only after backend is healthy
- [ ] Error state shows after 30s timeout
- [ ] Retry button works

---

#### Task 3.3: Add Tauri Desktop Notifications
**Status**: todo
**Feature**: tauri

**Description**: When a new high-priority notification arrives, send a native desktop notification via `tauri-plugin-notification`. The WebSocket handler already has a comment `// Could trigger a system notification here via Tauri`.

1. Import `@tauri-apps/plugin-notification` in the frontend
2. Request notification permission on first launch
3. Send native notifications for new `urgent` and `high` priority items
4. Clicking the notification should focus the app window and select the notification

**Files**:
- Modify: `src/lib/ws.ts` - trigger Tauri notification on `new_notification`
- Modify: `src/routes/+layout.svelte` - request permission on mount

**Acceptance Criteria**:
- [ ] Native desktop notification appears for urgent/high items
- [ ] Notification shows sender name and title
- [ ] App is not already focused when notification triggers (avoid duplicates)

---

### Phase 4: Frontend Polish & Integration Testing

#### Task 4.1: Fix Frontend-Backend API Contract Mismatches
**Status**: todo
**Feature**: integration

**Description**: Verify that the TypeScript types in `src/lib/types/index.ts` exactly match the Python Pydantic models in `backend/models/notification.py`. Check:

1. All enum values match (Source, NotificationType, Priority, TriageStatus)
2. Notification field names match (Python uses snake_case, need to verify JSON serialization)
3. WebSocketMessage event names match between backend `send_*` methods and frontend `handleMessage()`
4. API request/response shapes match between `api.ts` and FastAPI endpoint schemas

**Files**:
- Read & compare: `src/lib/types/index.ts` vs `backend/models/notification.py`
- Read & compare: `src/lib/api.ts` vs `backend/main.py` endpoints
- Read & compare: `src/lib/ws.ts` handler vs `backend/ws/manager.py`
- Modify as needed to align contracts

**Acceptance Criteria**:
- [ ] All TypeScript types match Python Pydantic model JSON output
- [ ] All API endpoints accept the shapes the frontend sends
- [ ] All WebSocket events are handled on both sides
- [ ] No runtime type errors in the console

---

#### Task 4.2: Add OAuth Setup UI to Frontend
**Status**: todo
**Feature**: auth-ui

**Description**: Users need a way to initiate OAuth from within the app. Add a setup/settings area:

1. Add a "Settings" button to the Sidebar (gear icon at bottom)
2. Create a `Settings.svelte` component/page
3. Show connection status for each service with "Connect" buttons
4. "Connect Gmail" opens the OAuth URL in the system browser (via Tauri shell plugin)
5. After OAuth completes, the backend callback stores tokens and the service auto-connects
6. Show green/red indicators for connected/disconnected services

**Files**:
- Create: `src/lib/components/Settings.svelte`
- Modify: `src/lib/components/Sidebar.svelte` - add settings button
- Modify: `src/routes/+page.svelte` - toggle between inbox and settings view
- Modify: `src/lib/stores/index.ts` - add `showSettings` store

**Acceptance Criteria**:
- [ ] Settings panel shows all service connection statuses
- [ ] "Connect Gmail" initiates OAuth flow
- [ ] "Connect Slack" shows workspace token input (Socket Mode uses bot tokens)
- [ ] Connected services show green indicators
- [ ] User can disconnect and reconnect services

---

#### Task 4.3: End-to-End Integration Test
**Status**: todo
**Feature**: testing

**Description**: Manual integration test checklist to verify the full flow:

1. Launch app with `npm run tauri dev`
2. Complete Gmail OAuth from Settings
3. Add Slack tokens to .env, restart
4. Verify notifications from both sources appear
5. Test keyboard navigation (j/k, arrow keys)
6. Test archive, snooze, mark-read
7. Test reply to Gmail email
8. Verify Slack notifications are read-only (no reply section shown)
9. Test search filtering
10. Test source filtering (sidebar)
11. Verify desktop notifications for high-priority items
12. Close and reopen app - verify triage state persists
13. Run `uv run ruff check .` - verify zero lint errors

**Validation**:
```bash
npm run tauri dev
# Follow manual test checklist above
```

**Acceptance Criteria**:
- [ ] All 13 test scenarios pass
- [ ] No console errors during normal usage
- [ ] App feels responsive (< 200ms for UI actions)

---

## Edge Cases

| Case | Expected Behavior | Coverage |
|------|-------------------|----------|
| Backend not running | Frontend shows "waiting for backend" splash | Task 3.2 |
| Invalid OAuth tokens | Service shows disconnected, "Reconnect" button available | Task 2.1, 4.2 |
| WebSocket disconnects | Auto-reconnect with exponential backoff (already implemented) | `ws.ts` |
| Slack workspace goes offline | Connection status turns red, auto-reconnect in 5s | `base.py` |
| Gmail rate limit (429) | Increase poll interval, show warning | Task 2.2 |
| Duplicate notifications | Dedup by `source_id` in both backend and frontend store | Task 2.2 |
| Very long email body | Truncate to 500 chars in notification, full in detail panel | Already handled |
| No credentials configured | Services skip initialization, app shows empty inbox with setup prompt | Task 4.2 |
| Orphan Python process | Tauri kills sidecar on window close | Task 3.1 |
| DB corruption | Delete `command_center.db`, fresh start | Manual recovery |

---

## Validation Approach

### Level 0: Security Scan
```bash
./scripts/security-scan.sh  # Trivy: secrets + dependency vulns
```

### Level 1: Static Analysis & Linting
```bash
cd backend && uv run ruff check . && uv run ruff format --check .
cd src-tauri && cargo check
npm run build  # SvelteKit type checking via Vite
```

### Level 2: Backend Health
```bash
cd backend && uv run uvicorn main:app --port 8766
curl http://127.0.0.1:8766/api/health
curl http://127.0.0.1:8766/api/services/status
```

### Level 3: WebSocket Connection
```bash
# In browser console or wscat:
wscat -c ws://127.0.0.1:8766/ws
# Should receive initial_load message
```

### Level 4: Build Verification
```bash
npm run build  # SvelteKit static build
cd src-tauri && cargo build  # Tauri binary
```

### Level 5: Full App
```bash
npm run tauri dev
# Complete manual test checklist (Task 4.3)
```

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Google OAuth redirect issues in Tauri | Medium | High | Use system browser for OAuth, not in-app webview |
| Slack Socket Mode token expiry | Low | Medium | App token doesn't expire; bot token has long TTL |
| Python sidecar fails to start | Medium | High | Health check polling with clear error message |
| SQLite locking with concurrent writes | Low | Medium | Use async SQLAlchemy with aiosqlite (already configured) |
| Tauri 2.x breaking changes | Low | Medium | Pin exact versions in Cargo.toml |
| Gmail Pub/Sub setup complexity | High | Low | Use polling (already implemented) for MVP, Pub/Sub later |
| uv not installed on user machine | Low | Medium | uv installs via `curl -LsSf https://astral.sh/uv/install.sh \| sh` - single command |

---

## Architecture Notes

### Data Flow
```
Gmail API / Slack Socket Mode
         ↓
  Python BaseService.listen()
         ↓
  BaseService.emit_notification()
         ↓
  ws_manager.send_notification()  →  Save to SQLite
         ↓
  WebSocket → Frontend
         ↓
  ws.ts handleMessage()
         ↓
  notifications.addOrUpdate()
         ↓
  Svelte reactive rendering
```

### Sidecar Architecture
```
Tauri App (Rust)
  ├── Spawns: uv run uvicorn main:app --port 8766
  ├── Opens: Webview → http://localhost:1420 (dev) / bundled HTML (prod)
  └── On close: kills Python process

Frontend (SvelteKit)
  ├── Polls: http://127.0.0.1:8766/api/health (startup)
  ├── Connects: ws://127.0.0.1:8766/ws (real-time)
  └── Calls: http://127.0.0.1:8766/api/* (actions)
```

---

## Research Findings

### From Codebase
- Service registry pattern in `main.py` cleanly manages lifecycle
- `BaseService._run_listener()` already implements auto-reconnect
- `ws_manager` singleton broadcasts to all connected frontends
- Notification dedup can leverage existing `source_id` field
- `TokenStore` model exists but has no CRUD helpers yet

### Tauri Sidecar Best Practices
- Use `tauri-plugin-shell` v2 with `Command::new_sidecar()`
- Set `"sidecar"` in `tauri.conf.json` under `plugins.shell`
- Kill child process in Tauri's `on_window_event` (CloseRequested)
- For production: bundle Python with PyInstaller or use Nuitka

### Gmail API
- OAuth 2.0 with `offline` access type for refresh tokens
- Scopes needed: `gmail.readonly`, `gmail.send`, `gmail.modify`
- History-based sync: `users.history.list(startHistoryId=...)` for incremental updates
- Pub/Sub push can be added later for real-time (requires Google Cloud setup)

### Slack Socket Mode (Read-Only)
- Requires `connections:write` scope on app token
- Bot token scopes (read-only): `channels:history`, `channels:read`, `im:history`, `im:read`, `users:read`
- `chat:write` scope NOT needed for MVP (read-only mode)
- (Nice-to-have) `channels:write` for `conversations.mark` (mark-as-read)
- Event subscriptions: `message.im`, `message.channels`, `app_mention`
- No public URL required (perfect for desktop apps)

### uv (Python Package Manager)
- `uv init` creates `pyproject.toml` with `[project]` and `[tool.uv]` sections
- `uv add <pkg>` adds to `[project.dependencies]` and installs
- `uv add --dev <pkg>` adds to `[tool.uv.dev-dependencies]`
- `uv sync` installs everything from lockfile into `.venv/`
- `uv run <cmd>` runs command inside the managed venv (no manual activation)
- Generates `uv.lock` lockfile for reproducible installs

### Ruff (Linting & Formatting)
- Config goes in `[tool.ruff]` section of `pyproject.toml`
- `ruff check .` for linting, `ruff format .` for formatting
- Recommended rules: `select = ["E", "F", "I", "UP", "B", "SIM"]`
- `target-version = "py311"` to match project Python version
- `line-length = 100` for slightly wider lines (good for async code)

---

*Ready for implementation with `/prp-implement .claude/PRPs/plans/command-center-e2e-mvp.plan.md`*
