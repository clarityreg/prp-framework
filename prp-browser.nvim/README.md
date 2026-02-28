# prp-browser.nvim

A lazygit-style floating TUI browser for the [PRP Framework](https://github.com/clarityreg/prp-framework) inside Neovim. Browse commands, agents, hooks, scripts, and all PRP components with a category tree on the left and live preview on the right.

## Features

- **Category tree** with 12 auto-discovered categories (commands, agents, hooks, observability, scripts, ralph, settings, etc.)
- **Live preview** with syntax highlighting via treesitter and metadata headers
- **Search/filter** across file names and descriptions
- **Export** individual files or entire categories to other projects
- **Yank** file paths to clipboard
- **Settings view** — edit `.claude/prp-settings.json` in-TUI with Plane API pickers
- **Security view** — run and browse claude-secure scan results
- **Vim-native navigation** — `j/k`, `h/l`, `Enter`, `Esc`

## Requirements

- Neovim >= 0.9
- [nui.nvim](https://github.com/MunifTanjim/nui.nvim)

## Installation

### lazy.nvim

```lua
{
  "clarityreg/prp-browser.nvim",
  dependencies = { "MunifTanjim/nui.nvim" },
  cmd = { "PRPBrowser" },
  keys = { { "<leader>pb", "<cmd>PRPBrowser<cr>", desc = "PRP Browser" } },
  config = function()
    require("prp-browser").setup({})
  end,
}
```

### Local development (from this repo)

```lua
{
  dir = "~/Development/prp-framework/prp-browser.nvim",
  dependencies = { "MunifTanjim/nui.nvim" },
  cmd = { "PRPBrowser" },
  keys = { { "<leader>pb", "<cmd>PRPBrowser<cr>", desc = "PRP Browser" } },
  config = function()
    require("prp-browser").setup({})
  end,
}
```

## Configuration

```lua
require("prp-browser").setup({
  width = 0.85,       -- float width as fraction of editor
  height = 0.85,      -- float height as fraction of editor
  tree_width = 35,    -- fixed width of tree panel in columns
  border = "rounded", -- border style: "rounded", "single", "double", "shadow"
  root_path = nil,    -- auto-detected from cwd (searches for .claude/commands/prp-core/)
})
```

## Usage

```
:PRPBrowser
```

Or with the default keymap: `<leader>pb`

## Keybindings

| Key | Action |
|-----|--------|
| `j` / `k` | Move down / up |
| `Enter` / `l` | Expand category or select item |
| `h` | Collapse category or jump to parent |
| `e` | Export selected item to a directory |
| `E` | Export entire category preserving structure |
| `y` | Yank file path to clipboard |
| `/` | Filter items by name or description |
| `Esc` | Clear filter (when filtered) or close |
| `q` | Close browser |
| `s` | Switch to Security scan view |
| `c` | Switch to Settings / config view |
| `o` | Switch to Observability dashboard view |
| `R` | Switch to Ralph autonomous loop view |
| `?` | Show help overlay |
| `Ctrl-d` / `Ctrl-u` | Scroll preview pane down / up |

## Categories

The browser auto-discovers files in these categories:

| Category | Path | Files |
|----------|------|-------|
| Commands | `.claude/commands/prp-core/` | PRP slash commands |
| Agents | `.claude/agents/` | Specialized agent prompts |
| Hooks | `.claude/hooks/` | Automation hooks (`.sh`, `.py`) |
| Observability Hooks | `.claude/hooks/observability/` | Dashboard event forwarding |
| Scripts (.claude) | `.claude/scripts/` | Git workflow scripts |
| Scripts (root) | `scripts/` | Pre-commit + observability scripts |
| Ralph | `ralph/` | Autonomous dev loop |
| Settings | `.claude/` | `settings*.json` files |
| Pre-commit | `.` | `.pre-commit-config.yaml` |
| PRPs | `.claude/PRPs/` | Artifacts (PRDs, plans, issues) |
| Observability Apps | `apps/` | Bun server + Vue dashboard |
| Root Config | `.` | `CLAUDE.md`, `.gitignore`, etc. |

## Highlight Groups

Override these in your colorscheme:

| Group | Default | Used for |
|-------|---------|----------|
| `PRPBrowserCategory` | Bold blue | Category headers |
| `PRPBrowserCategoryEmpty` | Bold dim | Empty categories |
| `PRPBrowserItem` | Light text | File items |
| `PRPBrowserPreviewTitle` | Bold purple | Preview file name |
| `PRPBrowserMetaKey` | Bold cyan | Metadata keys |
| `PRPBrowserMetaValue` | Green | Metadata values |
| `PRPSecurityRiskCritical` | Bold red | Risk label: CRITICAL |
| `PRPSecurityRiskHigh` | Bold orange | Risk label: HIGH |
| `PRPSecurityRiskMedium` | Bold yellow | Risk label: MEDIUM |
| `PRPSecurityRiskLow` | Bold green | Risk label: LOW |
| `PRPSettingsSection` | Bold blue | Settings section headers |
| `PRPSettingsKey` | Bold cyan | Settings field names |
| `PRPSettingsValue` | Green | Settings field values |
| `PRPSettingsConnected` | Bold green | Plane connection: OK |
| `PRPSettingsDisconnected` | Bold red | Plane connection: error |

## Settings View

Press `c` from the browser to open the settings view, which lets you read and write `.claude/prp-settings.json` without leaving Neovim.

### Settings keymaps

| Key | Action |
|-----|--------|
| `j` / `k` | Move down / up |
| `Enter` | Edit the selected field |
| `p` | Pick Plane project ID from the API |
| `t` | Pick Plane backlog state ID from the API |
| `w` | Save all settings to disk |
| `r` | Test Plane API connection |
| `b` / `Esc` | Back to browser view |
| `?` | Settings help overlay |
| `q` | Close browser |

### Plane API key

The Plane API key is **never** stored in `prp-settings.json`. It is read at runtime from a `.env` file in the project root:

```bash
# .env
PLANE_API_KEY=your_key_here
```

The pickers (`p` and `t`) require `plane.workspace_slug` (and `plane.project_id` for state picking) to be set first.

## Observability View

Press `o` from the browser to open the observability view. This connects to the local observability dashboard server (Bun + SQLite on port 4000) and displays recent Claude Code hook events in real-time.

### Observability keymaps

| Key | Action |
|-----|--------|
| `j` / `k` | Move down / up |
| `r` | Refresh server status and fetch events |
| `S` | Start the observability server |
| `X` | Stop the observability server |
| `d` | Open the Vue dashboard in your browser |
| `b` / `Esc` | Back to browser view |
| `?` | Observability help overlay |
| `q` | Close browser |

### Server control

The view can start and stop the observability server directly using the `scripts/start-observability.sh` and `scripts/stop-observability.sh` scripts. The server status is shown at the top of the view with a green/red indicator.

### Event preview

Select an event in the list to see full details in the preview pane, including event type, source app, timestamp, session ID, tool name, and raw JSON data.

## Ralph View

Press `R` from the browser to open the Ralph autonomous loop view. This shows the status of the Ralph development loop, including available modes, implementation plan progress, and Ralph configuration files.

### Ralph keymaps

| Key | Action |
|-----|--------|
| `j` / `k` | Move down / up |
| `Enter` | Open selected Ralph file in editor |
| `r` | Reload Ralph data from disk |
| `b` / `Esc` | Back to browser view |
| `?` | Ralph help overlay |
| `q` | Close browser |

### What's shown

- **Progress bar** — visual indicator of implementation plan completion
- **Loop Modes** — unified, plan, build, verify with commands
- **Implementation Plan** — task checklist from `IMPLEMENTATION_PLAN.md`
- **Ralph Files** — all files in the `ralph/` directory with preview

## Troubleshooting

### "PRP framework not found" error

The plugin searches upward from your current directory for `.claude/commands/prp-core/`. If not found, it falls back to git root + `.claude/`.

**Fix:** Either `cd` into the PRP project root, or set `root_path` explicitly:

```lua
require("prp-browser").setup({
  root_path = "~/Development/prp-framework",
})
```

### Security view: "claude_secure.py not found"

The security view needs the [claude-secure](https://github.com/clarityreg/claude-secure) scanner. Set the path in your config or `prp-settings.json`:

```lua
require("prp-browser").setup({
  claude_secure_path = "~/Development/claude-secure/claude_secure.py",
})
```

### Plane API: "Connection failed" in settings view

1. Ensure `.env` exists in the project root with `PLANE_API_KEY=your_key`
2. Set `plane.workspace_slug` first (press `Enter` on the field to edit)
3. Press `r` to refresh the connection status
4. Check the API URL matches your Plane instance (default: `https://api.plane.so/api/v1`)

### Large PRPs directory is slow

If `.claude/PRPs/` has many artifacts, the browser may take a moment to scan. The plugin reads file contents for metadata extraction — large files are truncated at 500 lines in preview.

**Tip:** Coverage reports and branch visualizations are gitignored by default (`.claude/PRPs/coverage/`, `.claude/PRPs/branches/`), which helps keep scan times down.

### Exporting categories to other projects

Press `E` on a category header to export all files in that category to another directory. The export preserves relative paths, so:

```
Export "Commands" to ~/other-project/.claude/
→ Creates ~/other-project/.claude/commands/prp-core/*.md
```

Press `e` on a single item to export just that file.
