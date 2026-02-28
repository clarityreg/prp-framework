local utils = require("prp-browser.utils")

local M = {}

-- Category definitions: order matters for display
M.categories = {
  {
    name = "Commands",
    icon = ">",
    dir = ".claude/commands/prp-core",
    pattern = "*.md",
    description = "PRP slash commands for Claude Code",
  },
  {
    name = "Agents",
    icon = "@",
    dir = ".claude/agents",
    pattern = "*.md",
    description = "Specialized agent prompt files",
  },
  {
    name = "Hooks",
    icon = "~",
    dir = ".claude/hooks",
    pattern = { "*.sh", "*.py" },
    description = "Automation hooks (format, audio, checks)",
  },
  {
    name = "Observability Hooks",
    icon = "o",
    dir = ".claude/hooks/observability",
    pattern = "*.py",
    description = "Dashboard event forwarding (send_event, model extractor)",
  },
  {
    name = "Scripts (.claude)",
    icon = "$",
    dir = ".claude/scripts",
    pattern = "*.py",
    description = "Git workflow scripts (branch guard, naming, etc.)",
  },
  {
    name = "Scripts (root)",
    icon = "$",
    dir = "scripts",
    pattern = { "*.sh", "*.py" },
    description = "Pre-commit + observability scripts",
  },
  {
    name = "Ralph",
    icon = "R",
    dir = "ralph",
    pattern = { "*.md", "*.sh" },
    description = "Autonomous development loop",
  },
  {
    name = "Settings",
    icon = "%",
    dir = ".claude",
    pattern = "settings*.json",
    description = "Claude Code settings files",
  },
  {
    name = "Pre-commit",
    icon = "#",
    dir = ".",
    pattern = ".pre-commit-config.yaml",
    description = "Pre-commit hook configuration",
  },
  {
    name = "PRPs",
    icon = "P",
    dir = ".claude/PRPs",
    pattern = "**/*.md",
    description = "Artifact storage (PRDs, plans, issues, reviews)",
  },
  {
    name = "Observability Apps",
    icon = "O",
    dir = "apps",
    pattern = { "server/package.json", "client/package.json", "server/src/*.ts", "client/src/*.ts", "client/src/*.vue" },
    description = "Bun server + Vue dashboard for hook event visualization",
  },
  {
    name = "Root Config",
    icon = ".",
    dir = ".",
    pattern = { "CLAUDE.md", ".gitignore", ".coderabbit.yaml", "pyproject.toml" },
    description = "Project-level configuration files",
  },
}

---@class ScanItem
---@field name string
---@field path string
---@field rel_path string
---@field filetype string
---@field category string
---@field metadata table|nil
---@field description string|nil

--- Scan the PRP framework root for all categorized files.
---@param root string
---@return { categories: table[], items: table<string, ScanItem[]> }
function M.scan(root)
  local result = { categories = {}, items = {} }

  for _, cat in ipairs(M.categories) do
    local items = {}
    local base = root .. "/" .. cat.dir
    local patterns = type(cat.pattern) == "table" and cat.pattern or { cat.pattern }

    for _, pat in ipairs(patterns) do
      local full_pattern = base .. "/" .. pat
      local files = vim.fn.glob(full_pattern, false, true)
      for _, filepath in ipairs(files) do
        -- Skip sound files and log files
        if not filepath:match("/sounds/") and not filepath:match("%.jsonl$") and not filepath:match("%.aiff$") then
          local rel = filepath:sub(#root + 2) -- strip root + /
          local item = M._build_item(filepath, rel, cat.name)
          table.insert(items, item)
        end
      end
    end

    -- Sort items by name
    table.sort(items, function(a, b)
      return a.name < b.name
    end)

    table.insert(result.categories, {
      name = cat.name,
      icon = cat.icon,
      description = cat.description,
      count = #items,
    })
    result.items[cat.name] = items
  end

  return result
end

function M._build_item(filepath, rel_path, category)
  local name = vim.fn.fnamemodify(filepath, ":t")
  local ft = utils.filetype_from_path(filepath)
  local item = {
    name = name,
    path = filepath,
    rel_path = rel_path,
    filetype = ft,
    category = category,
    metadata = nil,
    description = nil,
  }

  -- Try to extract metadata
  local content = utils.read_file(filepath)
  if content then
    if ft == "markdown" then
      local meta, _ = utils.parse_frontmatter(content)
      if next(meta) then
        item.metadata = meta
      end
      -- Use first heading or first non-empty line as description
      local heading = content:match("#%s+(.-)[\n\r]")
      if heading then
        item.description = heading
      end
    elseif ft == "python" or ft == "bash" then
      item.description = utils.extract_docstring(content, ft)
      if item.description and #item.description > 120 then
        item.description = item.description:sub(1, 117) .. "..."
      end
    elseif ft == "json" then
      item.description = "JSON configuration"
    end
  end

  return item
end

return M
