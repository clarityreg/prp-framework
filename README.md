# ⚡ Command Center

A unified desktop notification hub built with **Tauri + Svelte + Python FastAPI**.

Aggregates notifications from Gmail (×3), Outlook, Slack (×2), Asana, and Plane into one triage-able feed.

## Architecture

```
Tauri Shell (Rust)  →  Svelte Frontend (JS)  ←WebSocket→  Python Backend (FastAPI)
                                                            ├── Gmail ×3
                                                            ├── Outlook ×1
                                                            ├── Slack ×2
                                                            ├── Asana ×1
                                                            └── Plane ×1
```

## Prerequisites

- **Node.js** 18+ and npm
- **Python** 3.11+
- **Rust** (install via [rustup](https://rustup.rs/))
- **Tauri CLI**: `cargo install tauri-cli`

## Quick Start

### 1. Install frontend dependencies

```bash
cd command-center
npm install
```

### 2. Set up Python backend

```bash
cd backend
python -m venv venv
source venv/bin/activate  # macOS/Linux
pip install -r requirements.txt

# Copy and fill in your API credentials
cp .env.example .env
# Edit .env with your real credentials
```

### 3. Run in development mode

**Terminal 1 — Python backend:**
```bash
cd backend
source venv/bin/activate
python -m uvicorn main:app --reload --port 8766
```

**Terminal 2 — Tauri + Svelte:**
```bash
npm run tauri dev
```

Or run both together:
```bash
npm run dev:all
```

## API Credentials Setup

### Gmail (Google Cloud)
1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a project, enable Gmail API
3. Create OAuth 2.0 credentials (Desktop app type)
4. Download and note the Client ID + Secret
5. For Pub/Sub (real-time): create a topic and subscription

### Outlook (Microsoft Azure)
1. Go to [Azure Portal](https://portal.azure.com/#blade/Microsoft_AAD_RegisteredApps)
2. Register a new app
3. Add "Mail.ReadWrite" API permission
4. Create a client secret
5. Note the Client ID, Secret, and Tenant ID

### Slack (Socket Mode)
1. Go to [Slack API](https://api.slack.com/apps) → Create New App
2. Enable Socket Mode (generates App Token)
3. Add Bot Token Scopes: `channels:history`, `channels:read`, `chat:write`, `im:history`, `im:read`, `users:read`
4. Install to each workspace
5. Note Bot Token + App Token per workspace

### Asana
1. Go to [Asana Developer Console](https://app.asana.com/0/developer-console)
2. Create a Personal Access Token
3. Note your Workspace GID and Project GID

### Plane
1. In your Plane instance → Settings → API
2. Create an API key
3. Note your workspace slug and project ID

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌘1-6` | Switch source filter |
| `⌘N` | Create new task |
| `↑/↓` or `j/k` | Navigate notifications |
| `⌘Enter` | Send reply / Create task |
| `Esc` | Close detail panel / modal |

## Project Structure

```
command-center/
├── src/                    # Svelte frontend
│   ├── lib/
│   │   ├── components/     # UI components
│   │   ├── stores/         # Svelte stores (state management)
│   │   ├── types/          # TypeScript type definitions
│   │   ├── api.ts          # REST API client
│   │   └── ws.ts           # WebSocket client
│   └── routes/
│       ├── +layout.svelte  # Root layout + theme
│       └── +page.svelte    # Main inbox page
├── src-tauri/              # Tauri/Rust shell
│   ├── src/main.rs
│   ├── Cargo.toml
│   └── tauri.conf.json
├── backend/                # Python FastAPI
│   ├── services/           # Service integrations
│   │   ├── base.py         # Abstract base service
│   │   ├── gmail_service.py
│   │   ├── outlook_service.py
│   │   ├── slack_service.py
│   │   ├── asana_service.py
│   │   └── plane_service.py
│   ├── models/
│   │   ├── notification.py # Unified notification schema
│   │   └── database.py     # SQLite persistence
│   ├── ws/
│   │   └── manager.py      # WebSocket manager
│   ├── config.py           # Settings from .env
│   ├── main.py             # FastAPI entry point
│   └── requirements.txt
└── package.json
```

## Next Steps (Phase 2)

- [ ] OAuth flow UI (in-app browser for auth)
- [ ] System tray with unread badge count
- [ ] Desktop notifications via Tauri
- [ ] Snooze timer with background wake-up
- [ ] Email compose (not just reply)
- [ ] Slack thread viewer
- [ ] Drag-and-drop priority reordering
- [ ] Customizable notification rules/filters
