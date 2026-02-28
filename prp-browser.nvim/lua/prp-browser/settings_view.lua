local config = require("prp-browser.config")

local M = {}

-- State
local settings_data = nil   -- raw parsed from JSON
local display_list = {}     -- flat list: section headers + field rows
local plane_status = nil    -- "ok", "error", or nil (unchecked)
local plane_projects = {}   -- list of {id, name} fetched from Plane API
local plane_states = {}     -- list of {id, name} fetched from Plane API

-- ---------------------------------------------------------------------------
-- Schema definition
-- ---------------------------------------------------------------------------

local SECTIONS = {
  {
    key = "project",
    label = "Project",
    fields = {
      { key = "name",         label = "Project Name",   description = "Project name used in task titles and reports",   type = "string" },
      { key = "type",         label = "Project Type",   description = 'Project type (e.g. "fullstack", "backend", "frontend")', type = "string" },
      { key = "backend_dir",  label = "Backend Dir",    description = "Relative path to the backend directory",          type = "string" },
      { key = "frontend_dir", label = "Frontend Dir",   description = "Relative path to the frontend directory",         type = "string" },
    },
  },
  {
    key = "plane",
    label = "Plane Integration",
    fields = {
      { key = "workspace_slug",   label = "Workspace Slug",   description = "Plane workspace slug (from the URL)",                    type = "string" },
      { key = "project_id",       label = "Project ID",        description = "Plane project ID. Press `p` to pick from API.",          type = "string", picker = "project" },
      { key = "backlog_state_id", label = "Backlog State ID",  description = "Backlog state for new tasks. Press `t` to pick from API.", type = "string", picker = "state" },
      { key = "api_url",          label = "API URL",           description = "Plane API base URL",                                     type = "string" },
    },
  },
  {
    key = "coverage",
    label = "Coverage",
    fields = {
      { key = "overall",  label = "Overall Target",  description = "Minimum overall coverage percentage (0-100)", type = "number" },
      { key = "critical", label = "Critical Target", description = "Minimum coverage for critical paths (0-100)", type = "number" },
    },
  },
  {
    key = "ci",
    label = "CI Configuration",
    fields = {
      { key = "use_npm_ci",      label = "Use npm ci",       description = "Use `npm ci` instead of `npm install` in CI pipelines", type = "boolean" },
      { key = "node_version",    label = "Node Version",     description = 'Node.js version for CI runners (e.g. "20")',            type = "string" },
      { key = "python_version",  label = "Python Version",   description = 'Python version for CI runners (e.g. "3.12")',           type = "string" },
    },
  },
  {
    key = "qa",
    label = "Quality Assurance",
    fields = {
      { key = "tests_must_pass", label = "Tests Must Pass",  description = "Require zero test failures to pass quality gate",    type = "boolean" },
      { key = "min_coverage",    label = "Min Coverage (%)",  description = "Minimum code coverage percentage (0-100)",           type = "number" },
      { key = "max_p0_bugs",     label = "Max P0 Bugs",       description = "Maximum open P0 (system down/data loss) bugs",       type = "number" },
      { key = "max_p1_bugs",     label = "Max P1 Bugs",       description = "Maximum open P1 (core feature broken) bugs",         type = "number" },
      { key = "tracking_csv",    label = "Tracking CSV",      description = "Path to test results CSV file",                      type = "string" },
      { key = "bug_dir",         label = "Bug Directory",      description = "Path to bug report storage directory",               type = "string" },
      { key = "report_dir",      label = "Report Directory",   description = "Path to QA report storage directory",                type = "string" },
    },
  },
  {
    key = "root",
    label = "Global",
    fields = {
      { key = "claude_secure_path", label = "Secure Scanner", description = "Path to claude_secure.py scanner script", type = "string" },
    },
  },
}

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

--- Read a single key=value from an .env file (never stored in JSON).
---@param env_path string
---@param key string
---@return string|nil
function M._read_env_key(env_path, key)
  local fh = io.open(env_path, "r")
  if not fh then return nil end
  for line in fh:lines() do
    local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
    if k == key then
      fh:close()
      v = v:match('^"(.*)"$') or v:match("^'(.*)'$") or v
      return v
    end
  end
  fh:close()
  return nil
end

--- Get a value from settings_data given a section key and field key.
---@param section_key string
---@param field_key string
---@return any
function M._get_value(section_key, field_key)
  if not settings_data then return nil end
  if section_key == "root" then
    return settings_data[field_key]
  elseif section_key == "coverage" then
    local cov = settings_data.coverage or {}
    return (cov.targets or {})[field_key]
  elseif section_key == "qa" then
    local qa = settings_data.qa or {}
    -- quality_gates fields are nested, other qa fields are top-level
    local gates_fields = { tests_must_pass = true, min_coverage = true, max_p0_bugs = true, max_p1_bugs = true }
    if gates_fields[field_key] then
      return (qa.quality_gates or {})[field_key]
    else
      return qa[field_key]
    end
  else
    return (settings_data[section_key] or {})[field_key]
  end
end

--- Write a value into settings_data for the given section/field.
---@param section_key string
---@param field_key string
---@param value any
function M._set_value(section_key, field_key, value)
  if not settings_data then return end
  if section_key == "root" then
    settings_data[field_key] = value
  elseif section_key == "coverage" then
    if not settings_data.coverage then settings_data.coverage = {} end
    if not settings_data.coverage.targets then settings_data.coverage.targets = {} end
    settings_data.coverage.targets[field_key] = value
  elseif section_key == "qa" then
    if not settings_data.qa then settings_data.qa = {} end
    local gates_fields = { tests_must_pass = true, min_coverage = true, max_p0_bugs = true, max_p1_bugs = true }
    if gates_fields[field_key] then
      if not settings_data.qa.quality_gates then settings_data.qa.quality_gates = {} end
      settings_data.qa.quality_gates[field_key] = value
    else
      settings_data.qa[field_key] = value
    end
  else
    if not settings_data[section_key] then settings_data[section_key] = {} end
    settings_data[section_key][field_key] = value
  end
end

-- ---------------------------------------------------------------------------
-- Data loading
-- ---------------------------------------------------------------------------

--- Load settings from JSON and build the flat display_list.
function M.load_settings()
  settings_data = config.load_prp_settings() or {}
  display_list = {}

  for _, section in ipairs(SECTIONS) do
    table.insert(display_list, {
      is_header = true,
      section   = section.key,
      label     = section.label,
    })

    for _, field in ipairs(section.fields) do
      local raw = M._get_value(section.key, field.key)
      local display_val
      if raw == nil then
        display_val = ""
      elseif type(raw) == "boolean" then
        display_val = raw and "true" or "false"
      else
        display_val = tostring(raw)
      end

      table.insert(display_list, {
        is_header = false,
        key       = field.key,
        label     = field.label,
        value     = display_val,
        raw_value = raw,
        section   = section.key,
        field     = field,
      })
    end
  end
end

-- ---------------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------------

--- Render the settings list into display lines and highlights.
---@param width number
---@return string[] lines
---@return table[] highlights
function M.render_list(width)
  local lines = {}
  local highlights = {}

  if not settings_data then
    table.insert(lines, "  Press r to load settings")
    return lines, highlights
  end

  -- Connection status line
  local status_line
  if plane_status == "ok" then
    status_line = " ● Plane: Connected"
    table.insert(highlights, { line = 1, col_start = 0, col_end = #status_line, group = "PRPSettingsConnected" })
  elseif plane_status == "error" then
    status_line = " ○ Plane: Disconnected"
    table.insert(highlights, { line = 1, col_start = 0, col_end = #status_line, group = "PRPSettingsDisconnected" })
  else
    status_line = " ○ Plane: (press r to check)"
  end
  table.insert(lines, status_line)

  table.insert(lines, " " .. string.rep("─", math.max(0, width - 2)))
  table.insert(highlights, { line = 2, col_start = 0, col_end = -1, group = "Comment" })

  for _, entry in ipairs(display_list) do
    local i = #lines + 1

    if entry.is_header then
      local line = " ▸ " .. entry.label
      table.insert(lines, line)
      table.insert(highlights, { line = i, col_start = 0, col_end = #line, group = "PRPSettingsSection" })
    else
      local label_col = "   " .. entry.label .. ":"
      -- Pad to column 24 for value alignment
      local padding = math.max(1, 24 - #label_col)
      local val_display = entry.value
      if val_display == nil or val_display == "" then
        val_display = "(unset)"
      end
      local max_val = width - #label_col - padding - 2
      if max_val > 0 and #val_display > max_val then
        val_display = val_display:sub(1, max_val - 1) .. "…"
      end
      local line = label_col .. string.rep(" ", padding) .. val_display
      table.insert(lines, line)
      local key_end = #label_col
      local val_start = #label_col + padding
      table.insert(highlights, { line = i, col_start = 0,         col_end = key_end,  group = "PRPSettingsKey" })
      table.insert(highlights, { line = i, col_start = val_start, col_end = #line,    group = "PRPSettingsValue" })
    end
  end

  return lines, highlights
end

--- Render the preview panel for a settings entry.
---@param entry table|nil
---@param buf number
function M.render_preview(entry, buf)
  local lines = {}
  local hl_marks = {}

  if not entry then
    lines = { "", "  Select a setting to see details" }
    vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
    return
  end

  if entry.is_header then
    -- Section overview
    table.insert(lines, " " .. entry.label)
    table.insert(hl_marks, { line = 0, group = "PRPSettingsSection" })
    table.insert(lines, " " .. string.rep("─", 50))
    table.insert(hl_marks, { line = 1, group = "Comment" })

    local count = 0
    for _, e in ipairs(display_list) do
      if not e.is_header and e.section == entry.section then
        count = count + 1
      end
    end
    table.insert(lines, "")
    table.insert(lines, "  " .. count .. " setting" .. (count == 1 and "" or "s") .. " in this section.")
    table.insert(lines, "")
    table.insert(lines, "  Press j/k to navigate to a field,")
    table.insert(lines, "  then Enter to edit.")
  else
    local field = entry.field or {}
    table.insert(lines, " " .. entry.label)
    table.insert(hl_marks, { line = 0, group = "PRPBrowserPreviewTitle" })
    table.insert(lines, " " .. string.rep("─", 50))
    table.insert(hl_marks, { line = 1, group = "Comment" })
    table.insert(lines, "")
    table.insert(lines, " Description:")
    table.insert(lines, "   " .. (field.description or "No description available."))
    table.insert(lines, "")
    table.insert(lines, " Type:    " .. (field.type or "string"))
    table.insert(lines, " Section: " .. entry.section)
    table.insert(lines, "")
    table.insert(lines, " Current value:")
    local val = (entry.value ~= nil and entry.value ~= "") and entry.value or "(unset)"
    table.insert(lines, "   " .. val)
    table.insert(hl_marks, { line = #lines - 1, group = "PRPSettingsValue" })
    table.insert(lines, "")

    if field.picker == "project" then
      if #plane_projects > 0 then
        table.insert(lines, " Available Projects (press p to pick):")
        for _, proj in ipairs(plane_projects) do
          local marker = (proj.id == entry.value) and " ✓" or "  "
          table.insert(lines, marker .. " " .. proj.name .. " (" .. proj.id .. ")")
        end
      else
        table.insert(lines, " Press p to pick project from Plane API.")
        table.insert(lines, " Press r to test Plane connection first.")
      end
    elseif field.picker == "state" then
      if #plane_states > 0 then
        table.insert(lines, " Available States (press t to pick):")
        for _, state in ipairs(plane_states) do
          local marker = (state.id == entry.value) and " ✓" or "  "
          table.insert(lines, marker .. " " .. state.name .. " (" .. state.id .. ")")
        end
      else
        table.insert(lines, " Press t to pick backlog state from Plane API.")
        table.insert(lines, " (Requires workspace_slug and project_id to be set.)")
      end
    else
      table.insert(lines, " Press Enter to edit this field.")
    end

    table.insert(lines, "")
    table.insert(lines, " Press w to save all settings to disk.")
  end

  vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

  local ns = vim.api.nvim_create_namespace("prp_settings_preview")
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, mark in ipairs(hl_marks) do
    pcall(vim.api.nvim_buf_add_highlight, buf, ns, mark.group, mark.line, mark.col_start or 0, mark.col_end or -1)
  end
end

-- ---------------------------------------------------------------------------
-- Editing
-- ---------------------------------------------------------------------------

--- Edit a settings field via vim.ui.input.
---@param entry table
---@param callback fun()  called after value is set (refresh display)
function M.edit_field(entry, callback)
  if not entry or entry.is_header then return end
  local field = entry.field or {}

  vim.ui.input({
    prompt  = entry.label .. ": ",
    default = entry.value or "",
  }, function(input)
    if input == nil then return end  -- user cancelled

    local new_val
    if field.type == "number" then
      new_val = tonumber(input)
      if new_val == nil then
        vim.notify("Invalid number: " .. input, vim.log.levels.WARN)
        return
      end
    elseif field.type == "boolean" then
      local lower = input:lower()
      if lower == "true" or lower == "1" or lower == "yes" then
        new_val = true
      elseif lower == "false" or lower == "0" or lower == "no" then
        new_val = false
      else
        vim.notify("Invalid boolean (use true/false): " .. input, vim.log.levels.WARN)
        return
      end
    else
      new_val = input
    end

    M._set_value(entry.section, entry.key, new_val)
    entry.value     = (type(new_val) == "boolean") and (new_val and "true" or "false") or tostring(new_val)
    entry.raw_value = new_val

    if callback then callback() end
  end)
end

-- ---------------------------------------------------------------------------
-- Plane API pickers
-- ---------------------------------------------------------------------------

--- Async: fetch Plane projects → vim.ui.select → callback(project_id).
---@param callback fun(project_id: string)
function M.pick_plane_project(callback)
  local plane     = (settings_data or {}).plane or {}
  local workspace = plane.workspace_slug or ""
  local api_url   = plane.api_url or "https://api.plane.so/api/v1"

  if workspace == "" then
    vim.notify("Set plane.workspace_slug before picking a project", vim.log.levels.WARN)
    return
  end

  local root    = config.options.root_path or config.detect_root()
  local api_key = M._read_env_key(root .. "/.env", "PLANE_API_KEY")
  if not api_key or api_key == "" then
    vim.notify("PLANE_API_KEY not found in .env", vim.log.levels.WARN)
    return
  end

  local url = api_url .. "/workspaces/" .. workspace .. "/projects/"
  M._curl_json(url, api_key, function(ok, parsed)
    if not ok then return end
    local projects = (type(parsed) == "table") and (parsed.results or parsed) or {}
    if type(projects) ~= "table" or #projects == 0 then
      vim.notify("No projects found in workspace", vim.log.levels.WARN)
      return
    end
    plane_projects = {}
    local choices = {}
    for _, p in ipairs(projects) do
      local name = p.name or p.identifier or p.id
      table.insert(plane_projects, { id = p.id, name = name })
      table.insert(choices, name .. "  [" .. p.id .. "]")
    end
    vim.ui.select(choices, { prompt = "Select Plane Project:" }, function(_, idx)
      if not idx then return end
      local proj = plane_projects[idx]
      if proj and callback then callback(proj.id) end
    end)
  end)
end

--- Async: fetch Plane states → vim.ui.select → callback(state_id).
---@param callback fun(state_id: string)
function M.pick_plane_state(callback)
  local plane      = (settings_data or {}).plane or {}
  local workspace  = plane.workspace_slug or ""
  local project_id = plane.project_id or ""
  local api_url    = plane.api_url or "https://api.plane.so/api/v1"

  if workspace == "" or project_id == "" then
    vim.notify("Set plane.workspace_slug and plane.project_id before picking a state", vim.log.levels.WARN)
    return
  end

  local root    = config.options.root_path or config.detect_root()
  local api_key = M._read_env_key(root .. "/.env", "PLANE_API_KEY")
  if not api_key or api_key == "" then
    vim.notify("PLANE_API_KEY not found in .env", vim.log.levels.WARN)
    return
  end

  local url = api_url .. "/workspaces/" .. workspace .. "/projects/" .. project_id .. "/states/"
  M._curl_json(url, api_key, function(ok, parsed)
    if not ok then return end
    local states = (type(parsed) == "table") and (parsed.results or parsed) or {}
    if type(states) ~= "table" or #states == 0 then
      vim.notify("No states found for this project", vim.log.levels.WARN)
      return
    end
    plane_states = {}
    local choices = {}
    for _, s in ipairs(states) do
      local name = s.name or s.id
      table.insert(plane_states, { id = s.id, name = name })
      table.insert(choices, name .. "  [" .. s.id .. "]")
    end
    vim.ui.select(choices, { prompt = "Select Backlog State:" }, function(_, idx)
      if not idx then return end
      local state = plane_states[idx]
      if state and callback then callback(state.id) end
    end)
  end)
end

--- Async: health-check the Plane workspace; sets plane_status.
---@param callback fun(ok: boolean, err?: string)
function M.check_plane_connection(callback)
  local plane     = (settings_data or {}).plane or {}
  local workspace = plane.workspace_slug or ""
  local api_url   = plane.api_url or "https://api.plane.so/api/v1"

  if workspace == "" then
    plane_status = "error"
    if callback then callback(false, "workspace_slug not set") end
    return
  end

  local root    = config.options.root_path or config.detect_root()
  local api_key = M._read_env_key(root .. "/.env", "PLANE_API_KEY")
  if not api_key or api_key == "" then
    plane_status = "error"
    if callback then callback(false, "PLANE_API_KEY not in .env") end
    return
  end

  local url = api_url .. "/workspaces/" .. workspace .. "/"
  local cmd = { "curl", "-s", "-o", "/dev/null", "-w", "%{http_code}",
                "-H", "X-Api-Key: " .. api_key, url }
  local chunks = {}
  vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      if data then
        for _, l in ipairs(data) do
          if l ~= "" then table.insert(chunks, l) end
        end
      end
    end,
    on_exit = function(_, code)
      vim.schedule(function()
        local http_code = table.concat(chunks, ""):match("%d+") or "0"
        if code == 0 and (http_code == "200" or http_code == "201") then
          plane_status = "ok"
          if callback then callback(true) end
        else
          plane_status = "error"
          if callback then callback(false, "HTTP " .. http_code) end
        end
      end)
    end,
  })
end

-- ---------------------------------------------------------------------------
-- Save
-- ---------------------------------------------------------------------------

--- Persist settings_data to .claude/prp-settings.json.
---@return boolean
function M.save_settings()
  if not settings_data then
    vim.notify("No settings loaded", vim.log.levels.WARN)
    return false
  end
  local ok = config.save_prp_settings(settings_data)
  if ok then
    vim.notify("Settings saved to .claude/prp-settings.json", vim.log.levels.INFO)
  else
    vim.notify("Failed to save settings", vim.log.levels.ERROR)
  end
  return ok
end

-- ---------------------------------------------------------------------------
-- Accessors
-- ---------------------------------------------------------------------------

function M.get_display_list()
  return display_list
end

function M.get_entry_at(index)
  return display_list[index]
end

--- Convert a 1-based cursor line to a display_list index (accounts for 2 header lines).
---@param cursor_line number
---@return number
function M.display_index_from_cursor(cursor_line)
  return cursor_line - 2
end

function M.reset()
  settings_data  = nil
  display_list   = {}
  plane_status   = nil
  plane_projects = {}
  plane_states   = {}
end

-- ---------------------------------------------------------------------------
-- Internal: shared curl helper
-- ---------------------------------------------------------------------------

--- Run curl and parse JSON response; calls callback(ok, parsed_table|nil).
---@param url string
---@param api_key string
---@param callback fun(ok: boolean, data: table|nil)
function M._curl_json(url, api_key, callback)
  local cmd = { "curl", "-s", "-H", "X-Api-Key: " .. api_key, url }
  local chunks = {}
  local jid = vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      if data then
        for _, l in ipairs(data) do
          if l ~= "" then table.insert(chunks, l) end
        end
      end
    end,
    on_exit = function(_, code)
      vim.schedule(function()
        if code ~= 0 then
          vim.notify("Plane API call failed (exit " .. code .. ")", vim.log.levels.ERROR)
          callback(false, nil)
          return
        end
        local json_str = table.concat(chunks, "\n")
        local ok, parsed = pcall(vim.fn.json_decode, json_str)
        if not ok then
          vim.notify("Failed to parse Plane API response", vim.log.levels.ERROR)
          callback(false, nil)
          return
        end
        callback(true, parsed)
      end)
    end,
  })
  if jid == 0 or jid == -1 then
    vim.notify("Failed to start curl. Is curl installed?", vim.log.levels.ERROR)
    callback(false, nil)
  end
end

return M
