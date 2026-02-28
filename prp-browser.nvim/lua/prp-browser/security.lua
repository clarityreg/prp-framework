local config = require("prp-browser.config")
local utils = require("prp-browser.utils")

local M = {}

-- State
local findings = {}        -- flat list of findings (parsed from JSON)
local display_list = {}    -- flat list: mix of severity headers + findings
local current_filter = nil -- nil = all, or one of CRITICAL/HIGH/MEDIUM/LOW
local report_data = nil    -- raw parsed report
local scan_job = nil       -- job ID of running scan

local SEVERITY_ORDER = { "CRITICAL", "HIGH", "MEDIUM", "LOW" }
local SEVERITY_ICONS = {
  CRITICAL = "!!",
  HIGH     = "! ",
  MEDIUM   = "~ ",
  LOW      = ". ",
}

-- ---------------------------------------------------------------------------
-- Data
-- ---------------------------------------------------------------------------

---@class SecurityFinding
---@field severity string
---@field category string
---@field message string
---@field file_path string
---@field line_number number
---@field context_snippet string
---@field in_comment boolean
---@field rel_path string  -- computed from file_path - target_dir

--- Parse JSON report output into findings list.
---@param json_str string
---@return boolean success
function M.parse_report(json_str)
  local ok, data = pcall(vim.fn.json_decode, json_str)
  if not ok or not data then
    return false
  end

  report_data = data
  findings = {}

  local target_dir = data.target_dir or ""
  if target_dir ~= "" and not target_dir:match("/$") then
    target_dir = target_dir .. "/"
  end

  for _, fr in ipairs(data.file_reports or {}) do
    for _, f in ipairs(fr.findings or {}) do
      local rel = f.file_path or ""
      if target_dir ~= "" and rel:sub(1, #target_dir) == target_dir then
        rel = rel:sub(#target_dir + 1)
      end
      table.insert(findings, {
        severity = f.severity or "LOW",
        category = f.category or "",
        message = f.message or "",
        file_path = f.file_path or "",
        line_number = f.line_number or 0,
        context_snippet = f.context_snippet or "",
        in_comment = f.in_comment or false,
        rel_path = rel,
      })
    end
  end

  -- Sort: severity order, then file path, then line number
  local sev_rank = {}
  for i, s in ipairs(SEVERITY_ORDER) do sev_rank[s] = i end

  table.sort(findings, function(a, b)
    local ra, rb = sev_rank[a.severity] or 99, sev_rank[b.severity] or 99
    if ra ~= rb then return ra < rb end
    if a.rel_path ~= b.rel_path then return a.rel_path < b.rel_path end
    return a.line_number < b.line_number
  end)

  M._rebuild_display()
  return true
end

--- Rebuild the display list (headers + items) based on current filter.
function M._rebuild_display()
  display_list = {}

  -- Group findings by severity
  local by_sev = {}
  for _, s in ipairs(SEVERITY_ORDER) do by_sev[s] = {} end

  for _, f in ipairs(findings) do
    if not current_filter or f.severity == current_filter then
      table.insert(by_sev[f.severity], f)
    end
  end

  for _, sev in ipairs(SEVERITY_ORDER) do
    local group = by_sev[sev]
    if #group > 0 then
      -- Insert severity header
      table.insert(display_list, {
        is_header = true,
        severity = sev,
        count = #group,
        expanded = true,
      })
      -- Insert findings
      for _, f in ipairs(group) do
        table.insert(display_list, {
          is_header = false,
          finding = f,
        })
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------------

--- Render the findings list into display lines and highlights.
---@param width number
---@return string[] lines
---@return table[] highlights
function M.render_list(width)
  local lines = {}
  local highlights = {}

  if not report_data then
    table.insert(lines, "  Press S to run a security scan")
    return lines, highlights
  end

  -- Summary line
  local risk = report_data.risk_level or "?"
  local score = report_data.aggregate_score or 0
  local summary = " Risk: " .. risk .. " (" .. score .. "/100)"
  table.insert(lines, summary)
  table.insert(highlights, {
    line = 1, col_start = 0, col_end = #summary,
    group = "PRPSecurityRisk" .. (risk:sub(1, 1) .. risk:sub(2):lower()),
  })

  table.insert(lines, " " .. string.rep("─", width - 2))
  table.insert(highlights, { line = 2, col_start = 0, col_end = -1, group = "Comment" })

  for _, entry in ipairs(display_list) do
    local i = #lines + 1

    if entry.is_header then
      local arrow = entry.expanded and "▼" or "▸"
      local line = " " .. arrow .. " " .. entry.severity .. " (" .. entry.count .. ")"
      table.insert(lines, line)
      table.insert(highlights, {
        line = i, col_start = 0, col_end = #line,
        group = "PRPSecuritySev" .. (entry.severity:sub(1, 1) .. entry.severity:sub(2):lower()),
      })
    else
      local f = entry.finding
      local loc = f.rel_path
      if f.line_number > 0 then
        loc = loc .. ":" .. f.line_number
      end
      local line = "   " .. SEVERITY_ICONS[f.severity] .. loc
      if #line > width then
        line = line:sub(1, width - 1) .. "…"
      end
      table.insert(lines, line)
      table.insert(highlights, {
        line = i, col_start = 0, col_end = #line,
        group = "PRPSecurityItem",
      })
    end
  end

  if #display_list == 0 and #findings == 0 then
    table.insert(lines, "")
    table.insert(lines, "  No findings. Project looks clean.")
  elseif #display_list == 0 then
    table.insert(lines, "")
    table.insert(lines, "  No findings for this filter.")
  end

  return lines, highlights
end

--- Render the preview panel for a finding.
---@param finding SecurityFinding
---@param buf number
function M.render_preview(finding, buf)
  if not finding then
    local lines = { "", "  Select a finding to see details" }
    vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
    return
  end

  local lines = {}
  local hl_marks = {}

  -- File header
  table.insert(lines, " " .. finding.rel_path)
  table.insert(hl_marks, { line = 0, group = "PRPBrowserPreviewTitle" })
  table.insert(lines, " " .. string.rep("─", 50))
  table.insert(hl_marks, { line = 1, group = "Comment" })

  -- File content with context around the finding line
  local content = utils.read_file(finding.file_path)
  if content and finding.line_number > 0 then
    local file_lines = vim.split(content, "\n")
    local target = finding.line_number
    local start_line = math.max(1, target - 8)
    local end_line = math.min(#file_lines, target + 8)

    for ln = start_line, end_line do
      local prefix
      if ln == target then
        prefix = string.format(">%3d│ ", ln)
      else
        prefix = string.format(" %3d│ ", ln)
      end
      local text = file_lines[ln] or ""
      table.insert(lines, prefix .. text)

      if ln == target then
        table.insert(hl_marks, {
          line = #lines - 1, group = "PRPSecurityHighlightLine",
        })
      end
    end
  elseif content then
    -- No line number — show first 20 lines
    local file_lines = vim.split(content, "\n")
    for i = 1, math.min(20, #file_lines) do
      table.insert(lines, string.format(" %3d│ ", i) .. file_lines[i])
    end
  else
    table.insert(lines, "")
    table.insert(lines, "  Could not read file: " .. finding.file_path)
  end

  -- Finding detail
  table.insert(lines, "")
  table.insert(lines, " " .. string.rep("─", 50))

  local detail_start = #lines
  table.insert(lines, " Severity: " .. finding.severity)
  table.insert(hl_marks, {
    line = detail_start, group = "PRPSecuritySev" .. (finding.severity:sub(1, 1) .. finding.severity:sub(2):lower()),
  })

  table.insert(lines, " Category: " .. finding.category)
  table.insert(lines, " Message:  " .. finding.message)
  if finding.in_comment then
    table.insert(lines, " Note:     Found in comment (reduced severity)")
  end
  if finding.context_snippet ~= "" then
    table.insert(lines, "")
    table.insert(lines, " Snippet:")
    table.insert(lines, "   " .. finding.context_snippet)
  end

  vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

  -- Apply highlights
  local ns = vim.api.nvim_create_namespace("prp_security_preview")
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, mark in ipairs(hl_marks) do
    pcall(vim.api.nvim_buf_add_highlight, buf, ns, mark.group, mark.line, mark.col_start or 0, mark.col_end or -1)
  end
end

-- ---------------------------------------------------------------------------
-- Scan runner
-- ---------------------------------------------------------------------------

--- Run claude-secure scan asynchronously.
---@param root string  project root to scan
---@param callback fun(success: boolean, err?: string)
function M.run_scan(root, callback)
  if scan_job then
    vim.notify("Scan already in progress", vim.log.levels.WARN)
    return
  end

  local cs_path = config.options.claude_secure_path or "claude_secure.py"
  local cmd = { "uv", "run", "python", cs_path, root, "--json" }

  local stdout_chunks = {}

  scan_job = vim.fn.jobstart(cmd, {
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
      scan_job = nil
      vim.schedule(function()
        local json_str = table.concat(stdout_chunks, "\n")
        if json_str == "" then
          callback(false, "No output from scanner (exit " .. exit_code .. ")")
          return
        end
        local ok = M.parse_report(json_str)
        if ok then
          callback(true)
        else
          callback(false, "Failed to parse scanner output")
        end
      end)
    end,
  })

  if scan_job == 0 or scan_job == -1 then
    scan_job = nil
    callback(false, "Failed to start scanner. Check claude_secure_path config.")
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

function M.get_finding_at(index)
  -- index into display_list, skip headers
  local entry = display_list[index]
  if entry and not entry.is_header then
    return entry.finding
  end
  return nil
end

--- Get the display list index (1-based) accounting for summary lines.
--- The first 2 lines are summary + separator, then display_list items.
---@param cursor_line number  1-based cursor position in buffer
---@return number  index into display_list (1-based), or 0 if on summary
function M.display_index_from_cursor(cursor_line)
  return cursor_line - 2  -- 2 summary lines at top
end

function M.set_filter(severity)
  current_filter = severity
  M._rebuild_display()
end

function M.clear_filter()
  current_filter = nil
  M._rebuild_display()
end

function M.is_scanning()
  return scan_job ~= nil
end

function M.reset()
  findings = {}
  display_list = {}
  current_filter = nil
  report_data = nil
  scan_job = nil
end

return M
