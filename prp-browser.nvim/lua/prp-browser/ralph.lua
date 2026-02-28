local config = require("prp-browser.config")
local utils = require("prp-browser.utils")

local M = {}

-- State
local display_list = {}    -- flat list: section headers + items
local plan_data = nil      -- parsed IMPLEMENTATION_PLAN.md
local agents_data = nil    -- raw AGENTS.md content
local ralph_job = nil      -- job ID of running ralph process

local MODES = {
  { key = "unified",  label = "Unified (Recommended)", desc = "Implement + test + verify in one loop", cmd = "./ralph/loop.sh" },
  { key = "plan",     label = "Planning",              desc = "Gap analysis and task planning only",    cmd = "./ralph/loop.sh plan 3" },
  { key = "build",    label = "Build (Legacy)",        desc = "Implementation only, no auto-testing",   cmd = "./ralph/loop.sh build 10" },
  { key = "verify",   label = "Verify",                desc = "Visual testing / verification only",     cmd = "./ralph/loop.sh verify 3" },
}

-- ---------------------------------------------------------------------------
-- Data loading
-- ---------------------------------------------------------------------------

--- Parse IMPLEMENTATION_PLAN.md to extract task status.
---@param root string
---@return table|nil  { total, done, pending, tasks[] }
function M._parse_plan(root)
  local path = root .. "/ralph/IMPLEMENTATION_PLAN.md"
  local content = utils.read_file(path)
  if not content then return nil end

  local tasks = {}
  for line in content:gmatch("[^\n]+") do
    local checked, text = line:match("^%s*%-%s*%[([xX ])%]%s*(.+)")
    if checked and text then
      table.insert(tasks, {
        done = (checked == "x" or checked == "X"),
        text = text,
      })
    end
  end

  local done_count = 0
  for _, t in ipairs(tasks) do
    if t.done then done_count = done_count + 1 end
  end

  return {
    total = #tasks,
    done = done_count,
    pending = #tasks - done_count,
    tasks = tasks,
    raw = content,
  }
end

--- Load Ralph data from filesystem.
---@param root string
function M.load_data(root)
  plan_data = M._parse_plan(root)
  agents_data = utils.read_file(root .. "/ralph/AGENTS.md")

  M._rebuild_display()
end

--- Rebuild display list.
function M._rebuild_display()
  display_list = {}

  -- Modes section
  table.insert(display_list, {
    is_header = true,
    label = "Loop Modes",
    section = "modes",
  })
  for _, mode in ipairs(MODES) do
    table.insert(display_list, {
      is_header = false,
      section = "modes",
      mode = mode,
    })
  end

  -- Plan status section
  table.insert(display_list, {
    is_header = true,
    label = "Implementation Plan",
    section = "plan",
  })

  if plan_data and plan_data.total > 0 then
    for _, task in ipairs(plan_data.tasks) do
      table.insert(display_list, {
        is_header = false,
        section = "plan",
        task = task,
      })
    end
  else
    table.insert(display_list, {
      is_header = false,
      section = "plan",
      empty = true,
    })
  end

  -- Files section
  table.insert(display_list, {
    is_header = true,
    label = "Ralph Files",
    section = "files",
  })
  local files = { "loop.sh", "PROMPT_unified.md", "PROMPT_plan.md", "PROMPT_build.md", "PROMPT_verify.md", "AGENTS.md", "IMPLEMENTATION_PLAN.md", "README.md" }
  for _, f in ipairs(files) do
    table.insert(display_list, {
      is_header = false,
      section = "files",
      filename = f,
    })
  end
end

-- ---------------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------------

--- Render the ralph list into display lines and highlights.
---@param width number
---@return string[] lines
---@return table[] highlights
function M.render_list(width)
  local lines = {}
  local highlights = {}

  -- Progress summary
  if plan_data and plan_data.total > 0 then
    local pct = math.floor((plan_data.done / plan_data.total) * 100)
    local bar_width = 10
    local filled = math.floor(bar_width * plan_data.done / plan_data.total)
    local bar = string.rep("█", filled) .. string.rep("░", bar_width - filled)
    local summary = " [" .. bar .. "] " .. pct .. "% (" .. plan_data.done .. "/" .. plan_data.total .. ")"
    table.insert(lines, summary)

    local group = "PRPSettingsConnected"
    if pct < 50 then group = "PRPSecurityRiskMedium" end
    if pct < 25 then group = "PRPSecurityRiskHigh" end
    if pct == 100 then group = "PRPSettingsConnected" end
    table.insert(highlights, { line = 1, col_start = 0, col_end = #summary, group = group })
  else
    local summary = " No implementation plan found"
    table.insert(lines, summary)
    table.insert(highlights, { line = 1, col_start = 0, col_end = #summary, group = "Comment" })
  end

  table.insert(lines, " " .. string.rep("─", math.max(0, width - 2)))
  table.insert(highlights, { line = 2, col_start = 0, col_end = -1, group = "Comment" })

  for _, entry in ipairs(display_list) do
    local i = #lines + 1

    if entry.is_header then
      local line = " ▸ " .. entry.label
      table.insert(lines, line)
      table.insert(highlights, { line = i, col_start = 0, col_end = #line, group = "PRPSettingsSection" })
    elseif entry.mode then
      local line = "   " .. entry.mode.label
      if #line > width then line = line:sub(1, width - 1) .. "…" end
      table.insert(lines, line)
      table.insert(highlights, { line = i, col_start = 0, col_end = #line, group = "PRPBrowserItem" })
    elseif entry.task then
      local marker = entry.task.done and " ✓ " or " ○ "
      local line = "  " .. marker .. entry.task.text
      if #line > width then line = line:sub(1, width - 1) .. "…" end
      table.insert(lines, line)
      local group = entry.task.done and "PRPSettingsConnected" or "PRPBrowserItem"
      table.insert(highlights, { line = i, col_start = 0, col_end = #line, group = group })
    elseif entry.empty then
      table.insert(lines, "   (no tasks)")
      table.insert(highlights, { line = i, col_start = 0, col_end = -1, group = "Comment" })
    elseif entry.filename then
      local line = "   " .. entry.filename
      table.insert(lines, line)
      table.insert(highlights, { line = i, col_start = 0, col_end = #line, group = "PRPBrowserItem" })
    end
  end

  return lines, highlights
end

--- Render preview for a selected entry.
---@param entry table|nil
---@param buf number
---@param root string
function M.render_preview(entry, buf, root)
  local lines = {}
  local hl_marks = {}

  if not entry then
    lines = { "", "  Select an item to see details" }
    vim.api.nvim_buf_set_option(buf, "modifiable", true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_buf_set_option(buf, "modifiable", false)
    return
  end

  if entry.is_header then
    table.insert(lines, " " .. entry.label)
    table.insert(hl_marks, { line = 0, group = "PRPSettingsSection" })
    table.insert(lines, " " .. string.rep("─", 50))
    table.insert(hl_marks, { line = 1, group = "Comment" })

    if entry.section == "modes" then
      table.insert(lines, "")
      table.insert(lines, "  Available loop modes for autonomous development.")
      table.insert(lines, "  Select a mode to see its command and description.")
      table.insert(lines, "")
      table.insert(lines, "  Usage:")
      table.insert(lines, "    ./ralph/loop.sh          # Unified (recommended)")
      table.insert(lines, "    ./ralph/loop.sh 10       # 10 iterations")
      table.insert(lines, "    ./ralph/loop.sh plan 3   # 3 planning iterations")
    elseif entry.section == "plan" then
      table.insert(lines, "")
      if plan_data then
        table.insert(lines, "  Total tasks:   " .. plan_data.total)
        table.insert(lines, "  Completed:     " .. plan_data.done)
        table.insert(lines, "  Remaining:     " .. plan_data.pending)
      else
        table.insert(lines, "  No IMPLEMENTATION_PLAN.md found.")
      end
    elseif entry.section == "files" then
      table.insert(lines, "")
      table.insert(lines, "  Ralph directory files.")
      table.insert(lines, "  Select a file to preview its contents.")
    end
  elseif entry.mode then
    table.insert(lines, " " .. entry.mode.label)
    table.insert(hl_marks, { line = 0, group = "PRPBrowserPreviewTitle" })
    table.insert(lines, " " .. string.rep("─", 50))
    table.insert(hl_marks, { line = 1, group = "Comment" })
    table.insert(lines, "")
    table.insert(lines, " Description:")
    table.insert(lines, "   " .. entry.mode.desc)
    table.insert(lines, "")
    table.insert(lines, " Command:")
    table.insert(lines, "   " .. entry.mode.cmd)
    table.insert(hl_marks, { line = #lines - 1, group = "PRPBrowserMetaValue" })
    table.insert(lines, "")
    table.insert(lines, " Iterations:")
    table.insert(lines, "   Append a number to limit iterations:")
    table.insert(lines, "   " .. entry.mode.cmd .. " 5")
  elseif entry.task then
    local status = entry.task.done and "Completed" or "Pending"
    table.insert(lines, " " .. status .. ": " .. entry.task.text)
    table.insert(hl_marks, { line = 0, group = entry.task.done and "PRPSettingsConnected" or "PRPBrowserPreviewTitle" })
    table.insert(lines, " " .. string.rep("─", 50))
    table.insert(hl_marks, { line = 1, group = "Comment" })
  elseif entry.filename then
    local filepath = root .. "/ralph/" .. entry.filename
    table.insert(lines, " " .. entry.filename)
    table.insert(hl_marks, { line = 0, group = "PRPBrowserPreviewTitle" })
    table.insert(lines, " " .. string.rep("─", 50))
    table.insert(hl_marks, { line = 1, group = "Comment" })

    local content = utils.read_file(filepath)
    if content then
      local file_lines = vim.split(content, "\n")
      local max_lines = math.min(#file_lines, 100)
      table.insert(lines, "")
      for i = 1, max_lines do
        table.insert(lines, " " .. (file_lines[i] or ""))
      end
      if #file_lines > max_lines then
        table.insert(lines, "")
        table.insert(lines, " ... (" .. (#file_lines - max_lines) .. " more lines)")
      end
    else
      table.insert(lines, "")
      table.insert(lines, "  File not found: " .. filepath)
    end
  end

  vim.api.nvim_buf_set_option(buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)

  local ns = vim.api.nvim_create_namespace("prp_ralph_preview")
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, mark in ipairs(hl_marks) do
    pcall(vim.api.nvim_buf_add_highlight, buf, ns, mark.group, mark.line, mark.col_start or 0, mark.col_end or -1)
  end
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

--- Convert cursor line to display_list index (accounts for 2 header lines).
---@param cursor_line number
---@return number
function M.display_index_from_cursor(cursor_line)
  return cursor_line - 2
end

function M.is_busy()
  return ralph_job ~= nil
end

function M.reset()
  display_list = {}
  plan_data = nil
  agents_data = nil
  ralph_job = nil
end

return M
