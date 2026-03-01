local M = {}

M.defaults = {
  width = 0.85,
  height = 0.85,
  tree_width = 35,
  border = "rounded",
  root_path = nil, -- auto-detected if nil
  claude_secure_path = nil, -- auto-detected: ~/Development/claude-secure/claude_secure.py
}

M.options = {}

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})
  if not M.options.root_path then
    M.options.root_path = M.detect_root()
  end
  if not M.options.claude_secure_path then
    M.options.claude_secure_path = M.detect_claude_secure()
  end
end

--- Auto-detect claude_secure.py location.
--- Priority: prp-settings.json > known paths > PATH lookup.
---@return string|nil
function M.detect_claude_secure()
  local root = M.options.root_path or M.detect_root()

  -- 1. Check prp-settings.json for explicit path
  local settings = M.load_prp_settings()
  if settings and settings.claude_secure_path then
    local p = vim.fn.expand(settings.claude_secure_path)
    if vim.fn.filereadable(p) == 1 then
      return p
    end
  end

  -- 2. Check known locations
  local known = {
    vim.fn.expand("~/Development/claude-secure/claude_secure.py"),
    root .. "/scripts/claude_secure.py",
    root .. "/.claude/scripts/claude_secure.py",
  }
  for _, p in ipairs(known) do
    if vim.fn.filereadable(p) == 1 then
      return p
    end
  end

  -- 3. Check PATH via which
  local which = vim.fn.systemlist("which claude_secure.py 2>/dev/null")[1]
  if which and which ~= "" and vim.fn.filereadable(which) == 1 then
    return which
  end

  return nil
end

function M.detect_root()
  -- Strategy 1: search upward from cwd for .claude/commands/prp-core/
  local markers = { ".claude/commands/prp-core" }
  local cwd = vim.fn.getcwd()
  local dir = cwd
  while dir ~= "/" do
    for _, marker in ipairs(markers) do
      if vim.fn.isdirectory(dir .. "/" .. marker) == 1 then
        return dir
      end
    end
    dir = vim.fn.fnamemodify(dir, ":h")
  end

  -- Strategy 2: git root
  local git_root = vim.fn.systemlist("git rev-parse --show-toplevel 2>/dev/null")[1]
  if git_root and vim.fn.isdirectory(git_root .. "/.claude") == 1 then
    return git_root
  end

  return cwd
end

--- Load and parse .claude/prp-settings.json from the project root.
---@return table|nil  Parsed settings table, or nil on failure.
function M.load_prp_settings()
  local root = M.options.root_path or M.detect_root()
  local path = root .. "/.claude/prp-settings.json"
  local fh = io.open(path, "r")
  if not fh then
    return nil
  end
  local content = fh:read("*a")
  fh:close()
  local ok, data = pcall(vim.fn.json_decode, content)
  if ok and type(data) == "table" then
    return data
  end
  return nil
end

--- Save settings table back to .claude/prp-settings.json.
---@param settings table  Settings to write.
---@return boolean success
function M.save_prp_settings(settings)
  local root = M.options.root_path or M.detect_root()
  local path = root .. "/.claude/prp-settings.json"
  local ok, encoded = pcall(vim.fn.json_encode, settings)
  if not ok then
    return false
  end
  local fh = io.open(path, "w")
  if not fh then
    return false
  end
  fh:write(encoded)
  fh:close()
  return true
end

return M
