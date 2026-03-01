--- doctor.lua — PRP Doctor view for prp-browser.nvim
--- Displays project health check results from scripts/doctor-report.py --json.
--- Follows the same module interface as security.lua.

local config = require("prp-browser.config")

local M = {}

-- State
local report_data = nil     -- parsed JSON report
local display_list = {}     -- flat list: group headers + check items
local current_filter = nil  -- nil = all, or "PASS"/"WARN"/"FAIL"
local check_job = nil       -- job ID of running check

local STATUS_ORDER = { "FAIL", "WARN", "PASS", "SKIP", "INFO" }
local STATUS_ICONS = {
  FAIL = "XX",
  WARN = "! ",
  PASS = "OK",
  SKIP = "- ",
  INFO = "i ",
}

-- ---------------------------------------------------------------------------
-- Data
-- ---------------------------------------------------------------------------

---@class DoctorCheck
---@field name string
---@field status string  -- PASS/WARN/FAIL/SKIP/INFO
---@field detail string
---@field fix string

--- Parse JSON report output into report data.
---@param json_str string
---@return boolean success
function M.parse_report(json_str)
  local ok, data = pcall(vim.fn.json_decode, json_str)
  if not ok or not data then
    return false
  end

  report_data = data
  M._rebuild_display()
  return true
end

--- Rebuild the display list based on current filter.
function M._rebuild_display()
  display_list = {}
  if not report_data or not report_data.groups then
    return
  end

  for _, group in ipairs(report_data.groups) do
    local filtered_checks = {}
    for _, check in ipairs(group.checks or {}) do
      if not current_filter or check.status == current_filter then
        table.insert(filtered_checks, check)
      end
    end

    if #filtered_checks > 0 then
      -- Insert group header
      table.insert(display_list, {
        is_header = true,
        group_name = group.name,
        count = #filtered_checks,
      })
      -- Insert checks
      for _, check in ipairs(filtered_checks) do
        table.insert(display_list, {
          is_header = false,
          check = check,
        })
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------------

--- Render the check list into display lines and highlights.
---@param width number
---@return string[] lines
---@return table[] highlights
function M.render_list(width)
  local lines = {}
  local highlights = {}

  if not report_data then
    table.insert(lines, "  Press r to run health checks")
    return lines, highlights
  end

  -- Score summary line
  local s = report_data.score or {}
  local pct = s.percentage or 0
  local summary = string.format(" Health: %d%% (%d pass, %d warn, %d fail)",
    pct, s.passed or 0, s.warns or 0, s.fails or 0)
  table.insert(lines, summary)

  local score_group = "PRPDoctorPass"
  if pct < 50 then
    score_group = "PRPDoctorFail"
  elseif pct < 80 then
    score_group = "PRPDoctorWarn"
  end
  table.insert(highlights, {
    line = 1, col_start = 0, col_end = #summary, group = score_group,
  })

  table.insert(lines, " " .. string.rep("\xe2\x94\x80", width - 2))
  table.insert(highlights, { line = 2, col_start = 0, col_end = -1, group = "Comment" })

  for _, entry in ipairs(display_list) do
    local i = #lines + 1

    if entry.is_header then
      local line = " \xe2\x96\xbc " .. entry.group_name .. " (" .. entry.count .. ")"
      table.insert(lines, line)
      table.insert(highlights, {
        line = i, col_start = 0, col_end = #line, group = "PRPDoctorGroup",
      })
    else
      local c = entry.check
      local icon = STATUS_ICONS[c.status] or "? "
      local line = "   " .. icon .. " " .. c.name
      if #line > width then
        line = line:sub(1, width - 1) .. "\xe2\x80\xa6"
      end
      table.insert(lines, line)

      local hl_group = "PRPDoctorItem"
      if c.status == "PASS" then
        hl_group = "PRPDoctorPass"
      elseif c.status == "WARN" then
        hl_group = "PRPDoctorWarn"
      elseif c.status == "FAIL" then
        hl_group = "PRPDoctorFail"
      elseif c.status == "SKIP" then
        hl_group = "PRPDoctorSkip"
      elseif c.status == "INFO" then
        hl_group = "PRPDoctorInfo"
      end
      table.insert(highlights, {
        line = i, col_start = 0, col_end = #line, group = hl_group,
      })
    end
  end

  if #display_list == 0 then
    table.insert(lines, "")
    if current_filter then
      table.insert(lines, "  No checks match filter: " .. current_filter)
    else
      table.insert(lines, "  No check results available.")
    end
  end

  return lines, highlights
end

--- Render the preview panel for a check item.
---@param check DoctorCheck|nil
---@param buf number
function M.render_preview(check, buf)
  if not check then
    local lines = { "", "  Select a check to see details" }
    vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
    return
  end

  local lines = {}
  local hl_marks = {}

  -- Header
  table.insert(lines, " " .. check.name)
  table.insert(hl_marks, { line = 0, group = "PRPBrowserPreviewTitle" })
  table.insert(lines, " " .. string.rep("\xe2\x94\x80", 50))
  table.insert(hl_marks, { line = 1, group = "Comment" })
  table.insert(lines, "")

  -- Status
  local status_line = " Status: " .. check.status
  table.insert(lines, status_line)
  local status_group = "PRPDoctorItem"
  if check.status == "PASS" then status_group = "PRPDoctorPass"
  elseif check.status == "WARN" then status_group = "PRPDoctorWarn"
  elseif check.status == "FAIL" then status_group = "PRPDoctorFail"
  elseif check.status == "SKIP" then status_group = "PRPDoctorSkip"
  elseif check.status == "INFO" then status_group = "PRPDoctorInfo"
  end
  table.insert(hl_marks, { line = #lines - 1, group = status_group })

  -- Detail
  table.insert(lines, "")
  table.insert(lines, " Detail:")
  -- Wrap detail text
  local detail = check.detail or ""
  if detail ~= "" then
    for _, seg in ipairs(M._wrap_text(detail, 60)) do
      table.insert(lines, "   " .. seg)
    end
  else
    table.insert(lines, "   (none)")
  end

  -- Fix suggestion
  if check.fix and check.fix ~= "" then
    table.insert(lines, "")
    table.insert(lines, " Fix:")
    table.insert(hl_marks, { line = #lines - 1, group = "PRPDoctorWarn" })
    for _, seg in ipairs(M._wrap_text(check.fix, 60)) do
      table.insert(lines, "   " .. seg)
    end
  end

  -- Score context (if report available)
  if report_data and report_data.score then
    local s = report_data.score
    table.insert(lines, "")
    table.insert(lines, " " .. string.rep("\xe2\x94\x80", 50))
    table.insert(lines, string.format(" Overall: %d%% (%d/%d pass, %d warn, %d fail)",
      s.percentage, s.passed, s.total, s.warns, s.fails))
  end

  vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

  -- Apply highlights
  local ns = vim.api.nvim_create_namespace("prp_doctor_preview")
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, mark in ipairs(hl_marks) do
    pcall(vim.api.nvim_buf_add_highlight, buf, ns, mark.group, mark.line, mark.col_start or 0, mark.col_end or -1)
  end
end

-- ---------------------------------------------------------------------------
-- Check runner
-- ---------------------------------------------------------------------------

--- Run doctor checks asynchronously.
---@param root string  project root
---@param callback fun(success: boolean, err?: string)
function M.run_checks(root, callback)
  if check_job then
    vim.notify("Health checks already in progress", vim.log.levels.WARN)
    return
  end

  local script = root .. "/scripts/doctor-report.py"
  local cmd = { "python3", script, "--json" }

  local stdout_chunks = {}

  check_job = vim.fn.jobstart(cmd, {
    cwd = root,
    stdout_buffered = true,
    on_stdout = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            table.insert(stdout_chunks, line)
          end
        end
      end
    end,
    on_exit = function(_, exit_code)
      check_job = nil
      vim.schedule(function()
        local json_str = table.concat(stdout_chunks, "\n")
        if json_str == "" then
          callback(false, "No output from doctor script (exit " .. exit_code .. ")")
          return
        end
        local ok = M.parse_report(json_str)
        if ok then
          callback(true)
        else
          callback(false, "Failed to parse doctor output")
        end
      end)
    end,
  })

  if check_job == 0 or check_job == -1 then
    check_job = nil
    callback(false, "Failed to start doctor script. Check scripts/doctor-report.py exists.")
  end
end

-- ---------------------------------------------------------------------------
-- Accessors
-- ---------------------------------------------------------------------------

function M.get_display_list()
  return display_list
end

function M.get_report()
  return report_data
end

function M.get_entry_at(index)
  local entry = display_list[index]
  if entry and not entry.is_header then
    return entry.check
  end
  return nil
end

--- Get the display list index (1-based) accounting for summary lines.
---@param cursor_line number  1-based cursor position in buffer
---@return number  index into display_list (1-based), or 0 if on summary
function M.display_index_from_cursor(cursor_line)
  return cursor_line - 2  -- 2 summary lines at top (score + separator)
end

function M.set_filter(status)
  current_filter = status
  M._rebuild_display()
end

function M.clear_filter()
  current_filter = nil
  M._rebuild_display()
end

function M.is_busy()
  return check_job ~= nil
end

function M.reset()
  report_data = nil
  display_list = {}
  current_filter = nil
  check_job = nil
end

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

--- Simple text wrapping.
---@param text string
---@param max_width number
---@return string[]
function M._wrap_text(text, max_width)
  if #text <= max_width then
    return { text }
  end

  local result = {}
  local remaining = text
  while #remaining > max_width do
    -- Find last space before max_width
    local break_at = max_width
    for i = max_width, 1, -1 do
      if remaining:sub(i, i) == " " then
        break_at = i
        break
      end
    end
    table.insert(result, remaining:sub(1, break_at))
    remaining = remaining:sub(break_at + 1)
  end
  if #remaining > 0 then
    table.insert(result, remaining)
  end
  return result
end

return M
