--- install.lua — PRP Install view for prp-browser.nvim
--- Provides a UI to install PRP components into a target project directory
--- by driving install-prp.sh with --components flag.

local config = require("prp-browser.config")

local M = {}

-- ── Component definitions (mirrors install-prp.sh) ──────────────────────────
local COMPONENTS = {
  { id = 1,  label = "Core commands",          desc = ".claude/commands/prp-core/ (21 command files)",                       default = true  },
  { id = 2,  label = "Hook scripts",           desc = ".claude/hooks/ (auto-format, logging, observability forwarding)",     default = true  },
  { id = 3,  label = "Git guard scripts",      desc = ".claude/scripts/ (branch guard, naming, commit scope, pre-push)",     default = true  },
  { id = 4,  label = "Skills",                 desc = ".claude/skills/ (test-nudge, decision-capture, security, context)",   default = true  },
  { id = 5,  label = "Agents",                 desc = ".claude/agents/ (code-simplifier, backend-architect, etc.)",          default = true  },
  { id = 6,  label = "CI templates",           desc = ".claude/templates/ci/ (ci.yml, deploy.yml, electron-release.yml)",    default = true  },
  { id = 7,  label = "Pre-commit config",      desc = ".pre-commit-config.yaml + scripts/ helpers (lint, size, trivy)",      default = true  },
  { id = 8,  label = "Settings & wiring",      desc = "settings.json + prp-settings.json (hook configuration)",             default = true  },
  { id = 9,  label = "Observability dashboard", desc = "apps/server/ + apps/client/ (Bun + Vue event dashboard)",            default = false },
  { id = 10, label = "Ralph loop",             desc = "ralph/ directory (autonomous development loop scripts)",              default = false },
}

-- ── State ────────────────────────────────────────────────────────────────────
local selected = {}        -- boolean per component id
local target_dir = ""      -- target project directory
local install_output = nil -- string: output from last install run
local is_installing = false
local display_list = {}    -- flat list for rendering

--- Reset all state.
function M.reset()
  selected = {}
  for _, c in ipairs(COMPONENTS) do
    selected[c.id] = c.default
  end
  target_dir = ""
  install_output = nil
  is_installing = false
  display_list = {}
end

-- Initialize on load
M.reset()

--- Build the display list for the tree panel.
local function build_display_list()
  display_list = {}

  -- Target directory row
  table.insert(display_list, {
    type = "target",
    label = "Target directory",
    value = target_dir ~= "" and target_dir or "(press Enter to set)",
  })

  -- Separator
  table.insert(display_list, { type = "separator", label = "" })

  -- Component toggles
  for _, c in ipairs(COMPONENTS) do
    table.insert(display_list, {
      type = "component",
      id = c.id,
      label = c.label,
      desc = c.desc,
      selected = selected[c.id],
    })
  end

  -- Separator
  table.insert(display_list, { type = "separator", label = "" })

  -- Quick actions
  table.insert(display_list, { type = "action", action = "all_on",  label = "Select all" })
  table.insert(display_list, { type = "action", action = "all_off", label = "Deselect all" })
  table.insert(display_list, { type = "action", action = "defaults", label = "Reset to defaults" })

  -- Separator
  table.insert(display_list, { type = "separator", label = "" })

  -- Install button
  table.insert(display_list, { type = "action", action = "install", label = ">>> Install PRP <<<" })
end

--- Render the tree panel list.
---@param width number
---@return string[], table[]
function M.render_list(width)
  build_display_list()

  local lines = {}
  local highlights = {}

  for i, entry in ipairs(display_list) do
    local line = ""

    if entry.type == "target" then
      local val = entry.value
      if #val > width - 20 then
        val = "..." .. val:sub(-(width - 23))
      end
      line = "  " .. entry.label .. ": " .. val
      table.insert(highlights, { line = i, group = "PRPSettingsKey", col_start = 2, col_end = 2 + #entry.label })
      table.insert(highlights, { line = i, group = "PRPSettingsValue", col_start = 2 + #entry.label + 2, col_end = -1 })

    elseif entry.type == "separator" then
      line = " " .. string.rep("─", width - 2)
      table.insert(highlights, { line = i, group = "Comment", col_start = 0, col_end = -1 })

    elseif entry.type == "component" then
      local check = entry.selected and "[x]" or "[ ]"
      local num = string.format("%2d", entry.id)
      line = "  " .. check .. " " .. num .. ". " .. entry.label
      if entry.selected then
        table.insert(highlights, { line = i, group = "PRPSettingsConnected", col_start = 2, col_end = 5 })
      else
        table.insert(highlights, { line = i, group = "PRPSettingsDisconnected", col_start = 2, col_end = 5 })
      end
      table.insert(highlights, { line = i, group = "Comment", col_start = 6, col_end = 10 })
      table.insert(highlights, { line = i, group = "PRPBrowserItem", col_start = 10, col_end = -1 })

    elseif entry.type == "action" then
      if entry.action == "install" then
        line = "  " .. entry.label
        table.insert(highlights, { line = i, group = "PRPInstallButton", col_start = 0, col_end = -1 })
      else
        line = "  " .. entry.label
        table.insert(highlights, { line = i, group = "PRPBrowserCategory", col_start = 0, col_end = -1 })
      end
    end

    -- Truncate to width
    if #line > width then
      line = line:sub(1, width - 1) .. "~"
    end
    table.insert(lines, line)
  end

  return lines, highlights
end

--- Get the display entry at a given cursor index.
---@param idx number
---@return table|nil
function M.get_entry_at(idx)
  if idx and idx >= 1 and idx <= #display_list then
    return display_list[idx]
  end
  return nil
end

--- Map cursor line to display index (1:1 in this view).
---@param cursor number
---@return number
function M.display_index_from_cursor(cursor)
  return cursor
end

--- Render preview for a given entry.
---@param entry table|nil
---@param bufnr number
function M.render_preview(entry, bufnr)
  local lines = {}

  if not entry then
    lines = { "", "  Select a component to see details" }
  elseif entry.type == "target" then
    lines = {
      "",
      "  Target Project Directory",
      "  " .. string.rep("─", 40),
      "",
      "  Current: " .. (target_dir ~= "" and target_dir or "(not set)"),
      "",
      "  Press Enter to set/change the target directory.",
      "  The directory should be a git repo where you",
      "  want to install PRP components.",
      "",
      "  The install script will:",
      "    - Back up existing settings.json",
      "    - Append PRP section to CLAUDE.md",
      "    - Rewrite --source-app to project name",
      "    - Make scripts executable",
      "    - Run pre-commit install if available",
    }
  elseif entry.type == "component" then
    lines = {
      "",
      "  " .. entry.label,
      "  " .. string.rep("─", 40),
      "",
      "  " .. entry.desc,
      "",
      "  Status: " .. (entry.selected and "SELECTED" or "not selected"),
      "",
      "  Press Enter or Space to toggle.",
    }
  elseif entry.type == "action" then
    if entry.action == "install" then
      -- Show summary of what will be installed
      local sel_names = {}
      for _, c in ipairs(COMPONENTS) do
        if selected[c.id] then
          table.insert(sel_names, "  [x] " .. c.label)
        else
          table.insert(sel_names, "  [ ] " .. c.label)
        end
      end

      lines = {
        "",
        "  Install PRP Framework",
        "  " .. string.rep("─", 40),
        "",
        "  Target: " .. (target_dir ~= "" and target_dir or "(NOT SET)"),
        "",
        "  Components:",
      }
      for _, name in ipairs(sel_names) do
        table.insert(lines, name)
      end
      table.insert(lines, "")
      table.insert(lines, "  Press Enter to install.")

      if install_output then
        table.insert(lines, "")
        table.insert(lines, "  " .. string.rep("─", 40))
        table.insert(lines, "  Last install output:")
        table.insert(lines, "")
        for out_line in install_output:gmatch("[^\n]+") do
          -- Strip ANSI escape codes for display
          local clean = out_line:gsub("\027%[[%d;]*m", "")
          table.insert(lines, "  " .. clean)
        end
      end
    elseif entry.action == "all_on" then
      lines = { "", "  Select all 10 components.", "", "  Press Enter to apply." }
    elseif entry.action == "all_off" then
      lines = { "", "  Deselect all components.", "", "  Press Enter to apply." }
    elseif entry.action == "defaults" then
      lines = { "", "  Reset to defaults (1-8 on, 9-10 off).", "", "  Press Enter to apply." }
    end
  elseif entry.type == "separator" then
    lines = { "" }
  end

  vim.api.nvim_set_option_value("modifiable", true, { buf = bufnr })
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr })
end

--- Toggle a component's selection.
---@param id number  Component ID (1-10)
function M.toggle_component(id)
  if id >= 1 and id <= #COMPONENTS then
    selected[id] = not selected[id]
  end
end

--- Set the target directory.
---@param dir string
function M.set_target_dir(dir)
  target_dir = dir
end

--- Get the target directory.
---@return string
function M.get_target_dir()
  return target_dir
end

--- Prompt user for the target directory.
---@param callback fun()
function M.prompt_target_dir(callback)
  vim.ui.input({
    prompt = "Target project directory: ",
    default = target_dir,
    completion = "dir",
  }, function(input)
    if input and input ~= "" then
      local expanded = vim.fn.expand(input)
      -- Resolve to absolute path
      if expanded:sub(1, 1) ~= "/" then
        expanded = vim.fn.getcwd() .. "/" .. expanded
      end
      expanded = vim.fn.resolve(expanded)

      if vim.fn.isdirectory(expanded) ~= 1 then
        vim.notify("Directory does not exist: " .. expanded, vim.log.levels.ERROR)
        return
      end

      target_dir = expanded
    end
    if callback then
      vim.schedule(callback)
    end
  end)
end

--- Select all components.
function M.select_all()
  for _, c in ipairs(COMPONENTS) do
    selected[c.id] = true
  end
end

--- Deselect all components.
function M.deselect_all()
  for _, c in ipairs(COMPONENTS) do
    selected[c.id] = false
  end
end

--- Reset selections to defaults.
function M.reset_defaults()
  for _, c in ipairs(COMPONENTS) do
    selected[c.id] = c.default
  end
end

--- Check if an install is currently running.
---@return boolean
function M.is_busy()
  return is_installing
end

--- Build the install-prp.sh command for the current selections.
---@return string|nil command, string|nil error
function M.build_command()
  if target_dir == "" then
    return nil, "No target directory set"
  end

  -- Find PRP source (the framework repo)
  local prp_source = config.options.root_path
  if not prp_source then
    return nil, "PRP framework root not detected"
  end

  local script = prp_source .. "/install-prp.sh"
  if vim.fn.filereadable(script) ~= 1 then
    return nil, "install-prp.sh not found at " .. script
  end

  -- Build component list
  local nums = {}
  for _, c in ipairs(COMPONENTS) do
    if selected[c.id] then
      table.insert(nums, tostring(c.id))
    end
  end

  if #nums == 0 then
    return nil, "No components selected"
  end

  local cmd = string.format(
    "bash %s --components %s %s 2>&1",
    vim.fn.shellescape(script),
    table.concat(nums, ","),
    vim.fn.shellescape(target_dir)
  )

  return cmd, nil
end

--- Run the install.
---@param callback fun(ok: boolean, output: string)
function M.run_install(callback)
  local cmd, cmd_err = M.build_command()
  if not cmd then
    callback(false, cmd_err or "Unknown error")
    return
  end

  is_installing = true
  install_output = nil

  vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if data then
        install_output = table.concat(data, "\n")
      end
    end,
    on_stderr = function(_, data)
      if data and not install_output then
        install_output = table.concat(data, "\n")
      end
    end,
    on_exit = function(_, exit_code)
      is_installing = false
      vim.schedule(function()
        if exit_code == 0 then
          callback(true, install_output or "Install completed successfully")
        else
          callback(false, install_output or "Install failed with exit code " .. exit_code)
        end
      end)
    end,
  })
end

--- Handle Enter key on the current entry.
---@param entry table
---@param refresh_callback fun()  Called after state changes to re-render
function M.handle_action(entry, refresh_callback)
  if not entry then return end

  if entry.type == "target" then
    M.prompt_target_dir(refresh_callback)

  elseif entry.type == "component" then
    M.toggle_component(entry.id)
    refresh_callback()

  elseif entry.type == "action" then
    if entry.action == "all_on" then
      M.select_all()
      refresh_callback()
    elseif entry.action == "all_off" then
      M.deselect_all()
      refresh_callback()
    elseif entry.action == "defaults" then
      M.reset_defaults()
      refresh_callback()
    elseif entry.action == "install" then
      if target_dir == "" then
        vim.notify("Set a target directory first", vim.log.levels.WARN)
        return
      end
      if is_installing then
        vim.notify("Install already in progress", vim.log.levels.WARN)
        return
      end

      -- Count selected
      local count = 0
      for _, c in ipairs(COMPONENTS) do
        if selected[c.id] then count = count + 1 end
      end
      if count == 0 then
        vim.notify("No components selected", vim.log.levels.WARN)
        return
      end

      vim.notify("Installing PRP (" .. count .. " components) into " .. target_dir .. "...", vim.log.levels.INFO)
      M.run_install(function(ok, output)
        if ok then
          vim.notify("PRP installed successfully!", vim.log.levels.INFO)
        else
          vim.notify("PRP install failed — see preview for details", vim.log.levels.ERROR)
        end
        refresh_callback()
      end)
    end
  end
end

return M
