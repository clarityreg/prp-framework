# prp-browser.nvim

A lazygit-style floating TUI browser for the [PRP Framework](https://github.com/clarityreg/prp-framework) inside Neovim. Browse commands, agents, hooks, scripts, and all PRP components with a category tree on the left and live preview on the right.

## Features

- **Category tree** with 10 auto-discovered categories (commands, agents, hooks, scripts, ralph, settings, etc.)
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
| `?` | Show help overlay |
| `Ctrl-d` / `Ctrl-u` | Scroll preview pane down / up |

## Categories

The browser auto-discovers files in these categories:

| Category | Path | Files |
|----------|------|-------|
| Commands | `.claude/commands/prp-core/` | PRP slash commands |
| Agents | `.claude/agents/` | Specialized agent prompts |
| Hooks | `.claude/hooks/` | Automation hooks (`.sh`, `.py`) |
| Scripts (.claude) | `.claude/scripts/` | Git workflow scripts |
| Scripts (root) | `scripts/` | Pre-commit supporting scripts |
| Ralph | `ralph/` | Autonomous dev loop |
| Settings | `.claude/` | `settings*.json` files |
| Pre-commit | `.` | `.pre-commit-config.yaml` |
| PRPs | `.claude/PRPs/` | Artifacts (PRDs, plans, issues) |
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
