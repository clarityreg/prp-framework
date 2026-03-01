--- install.lua — PRP Install view for prp-browser.nvim
--- Provides a UI to install PRP components into a target project directory
--- by driving install-prp.sh with --components flag.

local config = require("prp-browser.config")

local M = {}

-- ── Component definitions (mirrors install-prp.sh) ──────────────────────────
local COMPONENTS = {
  { id = 1,  label = "Core commands",          desc = ".claude/commands/prp-core/ (29 command files)",                       default = true  },
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

-- ── Constants ────────────────────────────────────────────────────────────────
local BACKUP_DIR = vim.fn.expand("~/Development/prp-backups")
local LOG_DIR = vim.fn.expand("~/.claude/logs")
local LOG_FILE = LOG_DIR .. "/prp-install.log"

--- Resolve the PRP framework source directory from the plugin's own location.
--- install.lua lives at <framework>/prp-browser.nvim/lua/prp-browser/install.lua
--- so the framework root is 4 levels up from this file.
---@return string|nil  Absolute path to PRP framework root, or nil
local function resolve_framework_dir()
  local source = debug.getinfo(1, "S").source
  if source and source:sub(1, 1) == "@" then
    -- Strip the leading "@" that Lua prepends to file paths
    local file_path = source:sub(2)
    -- Go up 4 levels: install.lua -> prp-browser/ -> lua/ -> prp-browser.nvim/ -> framework/
    local framework_dir = vim.fn.fnamemodify(file_path, ":h:h:h:h")
    if vim.fn.filereadable(framework_dir .. "/install-prp.sh") == 1 then
      return framework_dir
    end
  end
  return nil
end

-- ── State ────────────────────────────────────────────────────────────────────
local selected = {}        -- boolean per component id
local target_dir = ""      -- target project directory
local plugin_dir = ""      -- path to prp-browser.nvim plugin directory
local install_output = nil -- string: output from last install run
local is_installing = false
local last_backup_path = nil -- path of last backup created
local last_status = nil    -- nil, "success", or "failed"
local last_error = nil     -- error message string if failed
local last_command = nil   -- the actual command that was run
local display_list = {}    -- flat list for rendering

--- Write a line to the persistent install log file.
---@param msg string
local function log(msg)
  vim.fn.mkdir(LOG_DIR, "p")
  local f = io.open(LOG_FILE, "a")
  if f then
    f:write(os.date("[%Y-%m-%d %H:%M:%S] ") .. msg .. "\n")
    f:close()
  end
end

--- Show a persistent message (survives NUI redraws) and also log it.
---@param msg string
---@param level number  vim.log.levels.*
local function notify_and_log(msg, level)
  log(msg)
  vim.notify(msg, level)
end

--- Reset all state.
function M.reset()
  selected = {}
  for _, c in ipairs(COMPONENTS) do
    selected[c.id] = c.default
  end
  target_dir = ""
  -- Auto-detect plugin directory from the framework root
  local framework = resolve_framework_dir()
  if framework and vim.fn.isdirectory(framework .. "/prp-browser.nvim") == 1 then
    plugin_dir = framework .. "/prp-browser.nvim"
  else
    plugin_dir = ""
  end
  install_output = nil
  is_installing = false
  last_backup_path = nil
  last_status = nil
  last_error = nil
  last_command = nil
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

  -- Use current directory shortcut
  table.insert(display_list, {
    type = "action",
    action = "use_cwd",
    label = "Use current directory (" .. vim.fn.fnamemodify(vim.fn.getcwd(), ":t") .. ")",
  })

  -- Separator
  table.insert(display_list, { type = "separator", label = "" })

  -- Plugin directory row
  table.insert(display_list, {
    type = "plugin_dir",
    label = "Neovim plugin path",
    value = plugin_dir ~= "" and plugin_dir or "(press Enter to set)",
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

  -- Install button — show status if available
  local install_label = ">>> Install PRP <<<"
  if is_installing then
    install_label = ">>> Installing... <<<"
  elseif last_status == "success" then
    install_label = ">>> INSTALL SUCCEEDED <<<"
  elseif last_status == "failed" then
    install_label = ">>> INSTALL FAILED (see preview) <<<"
  end
  table.insert(display_list, { type = "action", action = "install", label = install_label })
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

    elseif entry.type == "plugin_dir" then
      local val = entry.value
      if #val > width - 22 then
        val = "..." .. val:sub(-(width - 25))
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
        local hl_group = "PRPInstallButton"
        if last_status == "success" then
          hl_group = "PRPSettingsConnected"
        elseif last_status == "failed" then
          hl_group = "PRPSettingsDisconnected"
        end
        table.insert(highlights, { line = i, group = hl_group, col_start = 0, col_end = -1 })
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
      "    - Back up existing .claude/ to ~/Development/prp-backups/",
      "    - Append PRP section to CLAUDE.md",
      "    - Rewrite --source-app to project name",
      "    - Make scripts executable",
      "    - Run pre-commit install if available",
      "",
      "  Tip: Use the 'Use current directory' option below",
      "  to quickly set the directory where Neovim was launched.",
    }
  elseif entry.type == "plugin_dir" then
    -- Shorten home dir for display
    local home = vim.fn.expand("~")
    local display_path = plugin_dir
    if plugin_dir ~= "" and display_path:sub(1, #home) == home then
      display_path = "~" .. display_path:sub(#home + 1)
    end

    lines = {
      "",
      "  Neovim Plugin Directory",
      "  " .. string.rep("\xe2\x94\x80", 40),
      "",
      "  Current: " .. (plugin_dir ~= "" and plugin_dir or "(not set)"),
      "",
      "  This is the path to the prp-browser.nvim plugin.",
      "  Your lazy.nvim config should point here.",
      "",
      "  Press Enter to change the path.",
      "",
      "  " .. string.rep("\xe2\x94\x80", 40),
      "  Add to ~/.config/nvim/lua/plugins/:",
      "",
      '  return {',
      '    dir = "' .. display_path .. '",',
      '    dependencies = { "MunifTanjim/nui.nvim" },',
      '    cmd = { "PRPBrowser" },',
      '    keys = {',
      '      { "<leader>pb", "<cmd>PRPBrowser<cr>",',
      '        desc = "PRP Browser" },',
      '    },',
      '    config = function()',
      '      require("prp-browser").setup({})',
      '    end,',
      '  }',
    }
  elseif entry.type == "component" then
    lines = {
      "",
      "  " .. entry.label,
      "  " .. string.rep("\xe2\x94\x80", 40),
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
        "  " .. string.rep("\xe2\x94\x80", 50),
      }

      -- Show last result prominently at the top
      if last_status == "success" then
        table.insert(lines, "")
        table.insert(lines, "  STATUS: SUCCESS")
        table.insert(lines, "  Installed into: " .. target_dir)
        if last_backup_path then
          table.insert(lines, "  Backup at: " .. last_backup_path)
        end
        table.insert(lines, "")
        table.insert(lines, "  " .. string.rep("\xe2\x94\x80", 50))
      elseif last_status == "failed" then
        table.insert(lines, "")
        table.insert(lines, "  STATUS: FAILED")
        if last_error then
          table.insert(lines, "  Error: " .. last_error)
        end
        if last_command then
          table.insert(lines, "")
          table.insert(lines, "  Command that was run:")
          table.insert(lines, "  " .. last_command)
        end
        table.insert(lines, "")
        table.insert(lines, "  Full log: " .. LOG_FILE)
        table.insert(lines, "")
        table.insert(lines, "  " .. string.rep("\xe2\x94\x80", 50))
      elseif is_installing then
        table.insert(lines, "")
        table.insert(lines, "  STATUS: INSTALLING...")
        table.insert(lines, "  " .. string.rep("\xe2\x94\x80", 50))
      end

      table.insert(lines, "")
      table.insert(lines, "  Target: " .. (target_dir ~= "" and target_dir or "(NOT SET)"))
      table.insert(lines, "")
      table.insert(lines, "  Components:")
      for _, name in ipairs(sel_names) do
        table.insert(lines, name)
      end

      -- Show backup info
      local has_claude = target_dir ~= "" and vim.fn.isdirectory(target_dir .. "/.claude") == 1
      if has_claude and not last_status then
        table.insert(lines, "")
        table.insert(lines, "  Existing .claude/ detected — will be backed up to:")
        table.insert(lines, "  " .. BACKUP_DIR .. "/")

        if vim.fn.isdirectory(target_dir .. "/.claude/worktrees") == 1 then
          table.insert(lines, "")
          table.insert(lines, "  .claude/worktrees/ will NOT be overwritten")
        end
      end

      if not last_status and not is_installing then
        table.insert(lines, "")
        table.insert(lines, "  Press Enter to install.")
        table.insert(lines, "  Log file: " .. LOG_FILE)
      end

      -- Show build_command diagnostics
      if not last_status and not is_installing then
        local test_cmd, test_err = M.build_command()
        if not test_cmd then
          table.insert(lines, "")
          table.insert(lines, "  PROBLEM: " .. (test_err or "unknown"))
        else
          table.insert(lines, "")
          table.insert(lines, "  Command preview:")
          -- Wrap long command
          if #test_cmd > 70 then
            table.insert(lines, "  " .. test_cmd:sub(1, 70))
            table.insert(lines, "    " .. test_cmd:sub(71))
          else
            table.insert(lines, "  " .. test_cmd)
          end
        end
      end

      -- Show install output log
      if install_output and install_output ~= "" then
        table.insert(lines, "")
        table.insert(lines, "  " .. string.rep("\xe2\x94\x80", 50))
        table.insert(lines, "  Install output:")
        table.insert(lines, "")
        local line_num = 0
        for out_line in install_output:gmatch("[^\n]+") do
          local clean = out_line:gsub("\027%[[%d;]*m", "")
          if clean ~= "" then
            line_num = line_num + 1
            table.insert(lines, "  " .. clean)
          end
        end
        if line_num == 0 then
          table.insert(lines, "  (no output captured)")
        end
      end
    elseif entry.action == "all_on" then
      lines = { "", "  Select all 10 components.", "", "  Press Enter to apply." }
    elseif entry.action == "all_off" then
      lines = { "", "  Deselect all components.", "", "  Press Enter to apply." }
    elseif entry.action == "defaults" then
      lines = { "", "  Reset to defaults (1-8 on, 9-10 off).", "", "  Press Enter to apply." }
    elseif entry.action == "use_cwd" then
      local cwd = vim.fn.getcwd()
      local has_claude = vim.fn.isdirectory(cwd .. "/.claude") == 1
      lines = {
        "",
        "  Use Current Directory",
        "  " .. string.rep("─", 40),
        "",
        "  Path: " .. cwd,
        "",
        "  .claude/ exists: " .. (has_claude and "YES (will be backed up)" or "no"),
        "",
        "  Press Enter to set this as the target.",
      }
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

--- Prompt user for the plugin directory path.
---@param callback fun()
function M.prompt_plugin_dir(callback)
  vim.ui.input({
    prompt = "Path to prp-browser.nvim: ",
    default = plugin_dir,
    completion = "dir",
  }, function(input)
    if input and input ~= "" then
      local expanded = vim.fn.expand(input)
      if expanded:sub(1, 1) ~= "/" then
        expanded = vim.fn.getcwd() .. "/" .. expanded
      end
      expanded = vim.fn.resolve(expanded)

      if vim.fn.isdirectory(expanded) ~= 1 then
        vim.notify("Directory does not exist: " .. expanded, vim.log.levels.ERROR)
        return
      end

      plugin_dir = expanded
      vim.notify("Plugin path set to: " .. expanded, vim.log.levels.INFO)
    end
    if callback then
      vim.schedule(callback)
    end
  end)
end

--- Get the plugin directory.
---@return string
function M.get_plugin_dir()
  return plugin_dir
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

--- Back up the existing .claude directory (and other PRP files) in the target.
--- Runs asynchronously to avoid blocking Neovim.
---@param dir string  The target directory to back up from
---@param callback fun(backup_path: string|nil)  Called with path or nil
function M.backup_existing(dir, callback)
  local claude_dir = dir .. "/.claude"
  if vim.fn.isdirectory(claude_dir) ~= 1 then
    callback(nil)
    return
  end

  local folder_name = vim.fn.fnamemodify(dir, ":t")
  local timestamp = os.date("%Y-%m-%d_%H-%M-%S")
  local backup_path = BACKUP_DIR .. "/" .. folder_name .. "-" .. timestamp

  -- Create backup directory
  vim.fn.mkdir(backup_path, "p")

  notify_and_log("[PRP Install] Backing up .claude/ ...", vim.log.levels.INFO)

  -- Build a shell command that does rsync + file copies in one shot
  local files_to_copy = {}
  for _, file in ipairs({ ".pre-commit-config.yaml", "CLAUDE.md" }) do
    local src = dir .. "/" .. file
    if vim.fn.filereadable(src) == 1 then
      table.insert(files_to_copy, string.format("cp %s %s/", vim.fn.shellescape(src), vim.fn.shellescape(backup_path)))
    end
  end

  local cmd = string.format(
    "rsync -a --exclude='__pycache__' --exclude='*.pyc' --exclude='node_modules' --exclude='.DS_Store' %s %s/",
    vim.fn.shellescape(claude_dir),
    vim.fn.shellescape(backup_path)
  )
  if #files_to_copy > 0 then
    cmd = cmd .. " && " .. table.concat(files_to_copy, " && ")
  end

  log("[PRP Install] Backup command: " .. cmd)

  local job_id = vim.fn.jobstart(cmd, {
    on_exit = function(_, exit_code)
      vim.schedule(function()
        if exit_code == 0 then
          notify_and_log("[PRP Install] Backup complete: " .. backup_path, vim.log.levels.INFO)
          callback(backup_path)
        else
          notify_and_log("[PRP Install] Backup failed (exit " .. exit_code .. ")", vim.log.levels.WARN)
          callback(nil)
        end
      end)
    end,
  })

  -- Handle jobstart failure — on_exit never fires in these cases
  if job_id == 0 then
    notify_and_log("[PRP Install] Backup: invalid command arguments", vim.log.levels.WARN)
    callback(nil)
  elseif job_id == -1 then
    notify_and_log("[PRP Install] Backup: command not executable (rsync missing?)", vim.log.levels.WARN)
    callback(nil)
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

  -- Find PRP source (the framework repo) — NOT the target project.
  -- The plugin lives inside the framework repo, so derive from our own file path.
  local prp_source = resolve_framework_dir()
  if not prp_source then
    return nil, "Cannot find PRP framework root (install-prp.sh) from plugin location"
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
    "bash %s --components %s %s",
    vim.fn.shellescape(script),
    table.concat(nums, ","),
    vim.fn.shellescape(target_dir)
  )

  return cmd, nil
end

--- Run the install with streaming output.
---@param callback fun(ok: boolean, output: string)
---@param progress_callback fun(line: string)|nil  Called per output line for live updates
function M.run_install(callback, progress_callback)
  local cmd, cmd_err = M.build_command()
  if not cmd then
    last_status = "failed"
    last_error = cmd_err or "Unknown error building command"
    notify_and_log("[PRP Install] ERROR: " .. last_error, vim.log.levels.ERROR)
    callback(false, last_error)
    return
  end

  -- Log the exact command for debugging
  last_command = cmd
  -- Start a fresh log section for this install run
  log("========================================")
  log("[PRP Install] START")
  log("[PRP Install] Command: " .. cmd)
  notify_and_log("[PRP Install] Running: " .. cmd, vim.log.levels.INFO)

  is_installing = true
  install_output = nil
  last_status = nil
  last_error = nil
  local output_lines = {}
  local line_count = 0
  local last_refresh = 0

  local job_id = vim.fn.jobstart(cmd, {
    -- Stream output line by line (NOT buffered)
    stdout_buffered = false,
    stderr_buffered = false,
    on_stdout = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            table.insert(output_lines, line)
            line_count = line_count + 1
            local clean = line:gsub("\027%[[%d;]*m", "")
            if clean ~= "" then
              log("[stdout] " .. clean)
              vim.schedule(function()
                vim.notify("[PRP Install] " .. clean, vim.log.levels.INFO)
                -- Throttle refresh to every 5 lines to avoid excessive re-rendering
                if progress_callback and (line_count - last_refresh) >= 5 then
                  last_refresh = line_count
                  progress_callback(clean)
                end
              end)
            end
          end
        end
      end
    end,
    on_stderr = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            table.insert(output_lines, "[stderr] " .. line)
            local clean = line:gsub("\027%[[%d;]*m", "")
            if clean ~= "" then
              log("[stderr] " .. clean)
              vim.schedule(function()
                vim.notify("[PRP Install] STDERR: " .. clean, vim.log.levels.WARN)
              end)
            end
          end
        end
      end
    end,
    on_exit = function(_, exit_code)
      is_installing = false
      install_output = table.concat(output_lines, "\n")

      -- Write full output to log file
      log("[PRP Install] Exit code: " .. exit_code)
      log("[PRP Install] Total lines: " .. line_count)
      if line_count == 0 then
        log("[PRP Install] WARNING: No output captured from script")
      end

      vim.schedule(function()
        if exit_code == 0 then
          last_status = "success"
          last_error = nil
          notify_and_log("[PRP Install] SUCCESS! (" .. line_count .. " lines)", vim.log.levels.INFO)
          callback(true, install_output)
        else
          last_status = "failed"
          last_error = "Exit code " .. exit_code
          -- Try to find the actual error in the last few lines
          local tail = {}
          for i = math.max(1, #output_lines - 5), #output_lines do
            local clean = (output_lines[i] or ""):gsub("\027%[[%d;]*m", "")
            if clean ~= "" then
              table.insert(tail, clean)
            end
          end
          if #tail > 0 then
            last_error = last_error .. "\nLast output: " .. table.concat(tail, " | ")
          end
          notify_and_log("[PRP Install] FAILED (exit " .. exit_code .. ")", vim.log.levels.ERROR)
          if #tail > 0 then
            notify_and_log("[PRP Install] Last lines: " .. table.concat(tail, " | "), vim.log.levels.ERROR)
          end
          notify_and_log("[PRP Install] Full log: " .. LOG_FILE, vim.log.levels.INFO)
          callback(false, install_output or last_error)
        end
        -- Final refresh to show result
        if progress_callback then
          progress_callback("")
        end
      end)
    end,
  })

  -- Check if job actually started
  if job_id == 0 then
    is_installing = false
    last_status = "failed"
    last_error = "Invalid command arguments. Command: " .. cmd
    notify_and_log("[PRP Install] ERROR: Invalid command arguments", vim.log.levels.ERROR)
    notify_and_log("[PRP Install] Command was: " .. cmd, vim.log.levels.ERROR)
    callback(false, last_error)
  elseif job_id == -1 then
    is_installing = false
    last_status = "failed"
    last_error = "Command not executable (bash not found?). Command: " .. cmd
    notify_and_log("[PRP Install] ERROR: Command not executable", vim.log.levels.ERROR)
    notify_and_log("[PRP Install] Command was: " .. cmd, vim.log.levels.ERROR)
    callback(false, last_error)
  else
    log("[PRP Install] Job started with ID: " .. job_id)
  end
end

--- Handle Enter key on the current entry.
---@param entry table
---@param refresh_callback fun()  Called after state changes to re-render
function M.handle_action(entry, refresh_callback)
  if not entry then return end

  if entry.type == "target" then
    M.prompt_target_dir(refresh_callback)

  elseif entry.type == "plugin_dir" then
    M.prompt_plugin_dir(refresh_callback)

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
    elseif entry.action == "use_cwd" then
      local cwd = vim.fn.getcwd()
      if vim.fn.isdirectory(cwd) == 1 then
        target_dir = cwd
        vim.notify("Target set to: " .. cwd, vim.log.levels.INFO)
      else
        vim.notify("Current directory is invalid", vim.log.levels.ERROR)
      end
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
      local sel_labels = {}
      for _, c in ipairs(COMPONENTS) do
        if selected[c.id] then
          count = count + 1
          table.insert(sel_labels, c.label)
        end
      end
      if count == 0 then
        vim.notify("No components selected", vim.log.levels.WARN)
        return
      end

      -- Reset status from previous run
      last_status = nil
      last_error = nil
      last_command = nil
      install_output = nil

      notify_and_log("[PRP Install] Target: " .. target_dir, vim.log.levels.INFO)
      notify_and_log("[PRP Install] Components (" .. count .. "): " .. table.concat(sel_labels, ", "), vim.log.levels.INFO)

      -- Validate the command can be built before doing backup
      local test_cmd, test_err = M.build_command()
      if not test_cmd then
        last_status = "failed"
        last_error = test_err
        notify_and_log("[PRP Install] ERROR: " .. test_err, vim.log.levels.ERROR)
        refresh_callback()
        return
      end
      notify_and_log("[PRP Install] Command: " .. test_cmd, vim.log.levels.INFO)

      -- Back up existing .claude/ if present (async)
      M.backup_existing(target_dir, function(backup_path)
        last_backup_path = backup_path

        notify_and_log("[PRP Install] Installing " .. count .. " components...", vim.log.levels.INFO)
        refresh_callback()

        M.run_install(function(ok, output)
          refresh_callback()
        end, function(_)
          -- Progress: refresh UI periodically (throttled in run_install)
          refresh_callback()
        end)
      end)
    end
  end
end

return M
