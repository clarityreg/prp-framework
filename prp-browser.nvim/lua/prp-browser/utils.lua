local M = {}

--- Parse YAML-style frontmatter from markdown content.
--- Handles simple `key: value` pairs between `---` fences.
---@param content string
---@return table<string, string> metadata
---@return string body (content after frontmatter)
function M.parse_frontmatter(content)
  local meta = {}
  local body = content

  local fm_start, fm_end = content:match("^()%-%-%-\n()")
  if not fm_start then
    return meta, body
  end

  local close_pos = content:find("\n%-%-%-", fm_end)
  if not close_pos then
    return meta, body
  end

  local fm_block = content:sub(fm_end, close_pos - 1)
  for line in fm_block:gmatch("[^\n]+") do
    local key, value = line:match("^(%w[%w_-]*):%s*(.+)$")
    if key then
      value = value:gsub("^['\"](.+)['\"]$", "%1") -- strip quotes
      meta[key] = value
    end
  end

  body = content:sub(close_pos + 4) -- skip past closing ---
  body = body:gsub("^\n+", "") -- trim leading newlines
  return meta, body
end

--- Extract leading comment block from a script file.
---@param content string
---@param filetype string
---@return string|nil description
function M.extract_docstring(content, filetype)
  if filetype == "python" then
    -- Triple-quoted docstring
    local doc = content:match('^"""(.-)"""')
    if not doc then
      doc = content:match("^'''(.-)'''")
    end
    if doc then
      return vim.trim(doc)
    end
    -- Leading # comments
    return M._extract_hash_comments(content)
  elseif filetype == "sh" or filetype == "bash" or filetype == "zsh" then
    -- Skip shebang, then collect # comments
    local after_shebang = content:gsub("^#![^\n]*\n", "")
    return M._extract_hash_comments(after_shebang)
  end
  return nil
end

function M._extract_hash_comments(content)
  local lines = {}
  for line in content:gmatch("[^\n]*") do
    local comment = line:match("^#%s?(.*)")
    if comment then
      table.insert(lines, comment)
    else
      break
    end
  end
  if #lines > 0 then
    return table.concat(lines, "\n")
  end
  return nil
end

--- Read file contents.
---@param path string
---@return string|nil
function M.read_file(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local content = f:read("*a")
  f:close()
  return content
end

--- Get filetype from extension.
---@param path string
---@return string
function M.filetype_from_path(path)
  local ext = path:match("%.(%w+)$")
  local map = {
    md = "markdown",
    py = "python",
    sh = "bash",
    lua = "lua",
    json = "json",
    yaml = "yaml",
    yml = "yaml",
    toml = "toml",
    js = "javascript",
    ts = "typescript",
    tsx = "typescriptreact",
  }
  return map[ext] or ext or ""
end

return M
