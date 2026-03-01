local config = require("prp-browser.config")

local M = {}

-- State
local server_status = nil   -- "ok", "error", or nil (unchecked)
local events = {}            -- recent events from the server
local display_list = {}      -- flat list: status header + event rows
local server_job = nil       -- job ID of running start/stop

local SERVER_URL = "http://localhost:4000"
local DASHBOARD_URL = "http://localhost:5173"

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

--- Shared curl helper (async).
---@param url string
---@param callback fun(ok: boolean, data: table|nil)
function M._curl_json(url, callback)
  local cmd = { "curl", "-s", "--max-time", "3", url }
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
          callback(false, nil)
          return
        end
        local json_str = table.concat(chunks, "\n")
        local ok, parsed = pcall(vim.fn.json_decode, json_str)
        if not ok then
          callback(false, nil)
          return
        end
        callback(true, parsed)
      end)
    end,
  })
  if jid == 0 or jid == -1 then
    callback(false, nil)
  end
end

-- ---------------------------------------------------------------------------
-- Data
-- ---------------------------------------------------------------------------

--- Check server health.
---@param callback fun(ok: boolean)
function M.check_health(callback)
  M._curl_json(SERVER_URL .. "/health", function(ok, data)
    if ok and data and data.status == "ok" then
      server_status = "ok"
      if callback then callback(true) end
    else
      server_status = "error"
      if callback then callback(false) end
    end
  end)
end

--- Fetch recent events from the server.
---@param callback fun(ok: boolean)
function M.fetch_events(callback)
  M._curl_json(SERVER_URL .. "/api/events?limit=50", function(ok, data)
    if ok and type(data) == "table" then
      events = data
      M._rebuild_display()
      if callback then callback(true) end
    else
      events = {}
      M._rebuild_display()
      if callback then callback(false) end
    end
  end)
end

--- Rebuild display list from events.
function M._rebuild_display()
  display_list = {}

  for _, ev in ipairs(events) do
    table.insert(display_list, {
      is_header = false,
      event = ev,
    })
  end
end

-- ---------------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------------

--- Render the observability list into display lines and highlights.
---@param width number
---@return string[] lines
---@return table[] highlights
function M.render_list(width)
  local lines = {}
  local highlights = {}

  -- Server status line
  local status_line
  if server_status == "ok" then
    status_line = " ● Server: Running (port 4000)"
    table.insert(highlights, { line = 1, col_start = 0, col_end = #status_line, group = "PRPSettingsConnected" })
  elseif server_status == "error" then
    status_line = " ○ Server: Stopped"
    table.insert(highlights, { line = 1, col_start = 0, col_end = #status_line, group = "PRPSettingsDisconnected" })
  else
    status_line = " ○ Server: (press r to check)"
  end
  table.insert(lines, status_line)

  -- Dashboard URL
  local dash_line = " Dashboard: " .. DASHBOARD_URL
  table.insert(lines, dash_line)
  table.insert(highlights, { line = 2, col_start = 0, col_end = #dash_line, group = "Comment" })

  table.insert(lines, " " .. string.rep("─", math.max(0, width - 2)))
  table.insert(highlights, { line = 3, col_start = 0, col_end = -1, group = "Comment" })

  if #display_list == 0 then
    if server_status == "ok" then
      table.insert(lines, "")
      table.insert(lines, "  No events yet.")
      table.insert(lines, "  Start a Claude Code session to generate events.")
    elseif server_status == "error" then
      table.insert(lines, "")
      table.insert(lines, "  Server is not running.")
      table.insert(lines, "  Press S to start the observability server.")
    else
      table.insert(lines, "")
      table.insert(lines, "  Press r to check server status.")
    end
    return lines, highlights
  end

  -- Event header
  local header = " Recent Events (" .. #events .. ")"
  table.insert(lines, header)
  table.insert(highlights, { line = #lines, col_start = 0, col_end = #header, group = "PRPSettingsSection" })

  for _, entry in ipairs(display_list) do
    local i = #lines + 1
    local ev = entry.event

    local event_type = ev.event_type or ev.eventType or "?"
    local source = ev.source_app or ev.sourceApp or ""
    local tool = ev.tool_name or ev.toolName or ""
    local ts = ev.timestamp or ev.created_at or ""

    -- Format timestamp to just time if it has a T
    local time_part = ts:match("T(%d+:%d+:%d+)") or ts:match("(%d+:%d+)") or ""

    local line
    if tool ~= "" then
      line = "  " .. time_part .. " " .. event_type .. " → " .. tool
    else
      line = "  " .. time_part .. " " .. event_type
    end

    if source ~= "" and source ~= "prp-framework" then
      line = line .. " [" .. source .. "]"
    end

    if #line > width then
      line = line:sub(1, width - 1) .. "…"
    end

    table.insert(lines, line)

    -- Color by event type
    local group = "PRPBrowserItem"
    if event_type == "SessionStart" or event_type == "SessionEnd" then
      group = "PRPSettingsSection"
    elseif event_type:match("^Pre") then
      group = "PRPBrowserMetaKey"
    elseif event_type:match("Failure") or event_type:match("Error") then
      group = "PRPSecurityRiskHigh"
    elseif event_type == "Stop" then
      group = "PRPBrowserMetaValue"
    end
    table.insert(highlights, { line = i, col_start = 0, col_end = #line, group = group })
  end

  return lines, highlights
end

--- Render the preview panel for an event.
---@param ev table|nil
---@param buf number
function M.render_preview(ev, buf)
  local lines = {}
  local hl_marks = {}

  if not ev then
    lines = { "", "  Select an event to see details" }
    vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
    return
  end

  local event_type = ev.event_type or ev.eventType or "?"
  table.insert(lines, " " .. event_type)
  table.insert(hl_marks, { line = 0, group = "PRPBrowserPreviewTitle" })
  table.insert(lines, " " .. string.rep("─", 50))
  table.insert(hl_marks, { line = 1, group = "Comment" })

  -- Standard fields
  local fields = {
    { "Event Type",  ev.event_type or ev.eventType },
    { "Source App",  ev.source_app or ev.sourceApp },
    { "Timestamp",   ev.timestamp or ev.created_at },
    { "Session ID",  ev.session_id or ev.sessionId },
    { "Tool Name",   ev.tool_name or ev.toolName },
    { "Agent ID",    ev.agent_id or ev.agentId },
    { "Error",       ev.error },
  }

  table.insert(lines, "")
  for _, pair in ipairs(fields) do
    local label, value = pair[1], pair[2]
    if value and value ~= "" then
      local kline = " " .. label .. ":"
      local padding = math.max(1, 16 - #kline)
      local vline = kline .. string.rep(" ", padding) .. tostring(value)
      table.insert(lines, vline)
      table.insert(hl_marks, { line = #lines - 1, col_start = 0, col_end = #kline, group = "PRPBrowserMetaKey" })
      table.insert(hl_marks, { line = #lines - 1, col_start = #kline + padding, col_end = #vline, group = "PRPBrowserMetaValue" })
    end
  end

  -- Raw JSON dump for extra fields
  table.insert(lines, "")
  table.insert(lines, " " .. string.rep("─", 50))
  table.insert(hl_marks, { line = #lines - 1, group = "Comment" })
  table.insert(lines, " Raw Data:")
  table.insert(hl_marks, { line = #lines - 1, group = "PRPBrowserMetaKey" })

  local ok, encoded = pcall(vim.fn.json_encode, ev)
  if ok then
    -- Pretty-print JSON (basic indentation)
    local pretty = encoded:gsub(",", ",\n  "):gsub("{", "{\n  "):gsub("}", "\n}")
    for line in pretty:gmatch("[^\n]+") do
      table.insert(lines, "  " .. line)
    end
  end

  vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

  local ns = vim.api.nvim_create_namespace("prp_observability_preview")
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, mark in ipairs(hl_marks) do
    pcall(vim.api.nvim_buf_add_highlight, buf, ns, mark.group, mark.line, mark.col_start or 0, mark.col_end or -1)
  end
end

-- ---------------------------------------------------------------------------
-- Server control
-- ---------------------------------------------------------------------------

--- Start the observability server.
---@param root string  project root
---@param callback fun(ok: boolean, msg?: string)
function M.start_server(root, callback)
  if server_job then
    vim.notify("Server operation already in progress", vim.log.levels.WARN)
    return
  end

  local script = root .. "/scripts/start-observability.sh"
  if vim.fn.filereadable(script) ~= 1 then
    if callback then callback(false, "start-observability.sh not found") end
    return
  end

  server_job = vim.fn.jobstart({ "bash", script }, {
    on_exit = function(_, code)
      server_job = nil
      vim.schedule(function()
        if code == 0 then
          server_status = "ok"
          if callback then callback(true) end
        else
          if callback then callback(false, "Script exited with code " .. code) end
        end
      end)
    end,
  })

  if server_job == 0 or server_job == -1 then
    server_job = nil
    if callback then callback(false, "Failed to start script") end
  end
end

--- Stop the observability server.
---@param root string  project root
---@param callback fun(ok: boolean, msg?: string)
function M.stop_server(root, callback)
  local script = root .. "/scripts/stop-observability.sh"
  if vim.fn.filereadable(script) ~= 1 then
    if callback then callback(false, "stop-observability.sh not found") end
    return
  end

  vim.fn.jobstart({ "bash", script }, {
    on_exit = function(_, code)
      vim.schedule(function()
        server_status = "error"
        if callback then callback(code == 0) end
      end)
    end,
  })
end

-- ---------------------------------------------------------------------------
-- Accessors
-- ---------------------------------------------------------------------------

function M.get_display_list()
  return display_list
end

function M.get_event_at(index)
  local entry = display_list[index]
  if entry and not entry.is_header then
    return entry.event
  end
  return nil
end

--- Convert cursor line to display_list index (accounts for 3 header lines: status, dashboard, separator).
---@param cursor_line number
---@return number
function M.display_index_from_cursor(cursor_line)
  return cursor_line - 4  -- 3 header lines + 1 section header
end

function M.get_status()
  return server_status
end

function M.is_busy()
  return server_job ~= nil
end

function M.reset()
  server_status = nil
  events = {}
  display_list = {}
  server_job = nil
end

return M
