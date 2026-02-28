local config = require("prp-browser.config")
local scanner = require("prp-browser.scanner")
local tree_mod = require("prp-browser.tree")
local preview = require("prp-browser.preview")
local actions = require("prp-browser.actions")
local security = require("prp-browser.security")
local settings_view = require("prp-browser.settings_view")
local observability = require("prp-browser.observability")
local ralph = require("prp-browser.ralph")

local Layout = require("nui.layout")
local Popup = require("nui.popup")

local M = {}

-- State
local layout = nil
local tree_popup = nil
local preview_popup = nil
local tree_nodes = nil       -- original (unfiltered) tree
local display_nodes = nil    -- possibly filtered tree
local flat_nodes = nil       -- flattened for display
local scan_result = nil
local current_filter = nil
local cursor_line = 1
local current_view = "browser" -- "browser", "security", "settings", "observability", or "ralph"

--- Open the PRP browser UI.
function M.open()
  if layout then
    vim.notify("PRP Browser is already open", vim.log.levels.WARN)
    return
  end

  local opts = config.options
  local root = opts.root_path
  if not root or vim.fn.isdirectory(root .. "/.claude") ~= 1 then
    vim.notify("PRP framework not found. Set root_path or cd to a PRP project.", vim.log.levels.ERROR)
    return
  end

  -- Scan files
  scan_result = scanner.scan(root)

  -- Build tree
  tree_nodes = tree_mod.build(scan_result)
  display_nodes = tree_nodes
  flat_nodes = tree_mod.flatten(display_nodes)

  -- Create popups
  tree_popup = Popup({
    border = {
      style = opts.border,
      text = {
        top = " PRP Browser ",
        top_align = "center",
      },
    },
    buf_options = {
      modifiable = false,
      readonly = true,
      buftype = "nofile",
      filetype = "prp-browser-tree",
    },
    win_options = {
      cursorline = true,
      number = false,
      relativenumber = false,
      wrap = false,
      signcolumn = "no",
    },
  })

  preview_popup = Popup({
    border = {
      style = opts.border,
      text = {
        top = " Preview ",
        top_align = "center",
      },
    },
    buf_options = {
      modifiable = false,
      readonly = true,
      buftype = "nofile",
    },
    win_options = {
      cursorline = false,
      number = true,
      relativenumber = false,
      wrap = true,
      signcolumn = "no",
    },
  })

  -- Create layout
  layout = Layout(
    {
      position = "50%",
      size = {
        width = math.floor(vim.o.columns * opts.width),
        height = math.floor(vim.o.lines * opts.height),
      },
      relative = "editor",
    },
    Layout.Box({
      Layout.Box(tree_popup, { size = opts.tree_width }),
      Layout.Box(preview_popup, { grow = 1 }),
    }, { dir = "row" })
  )

  layout:mount()

  -- Render tree
  current_view = "browser"
  M._render_tree()

  -- Set cursor to first line
  cursor_line = 1
  pcall(vim.api.nvim_win_set_cursor, tree_popup.winid, { 1, 0 })

  -- Preview first item
  M._update_preview()

  -- Setup keymaps
  M._setup_keymaps()

  -- Setup autocmd for cursor movement -> preview update
  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = tree_popup.bufnr,
    callback = function()
      local pos = vim.api.nvim_win_get_cursor(tree_popup.winid)
      if pos[1] ~= cursor_line then
        cursor_line = pos[1]
        M._update_preview()
      end
    end,
  })

  -- Status line at bottom of tree
  M._render_status()
end

--- Close the PRP browser UI.
function M.close()
  if layout then
    layout:unmount()
    layout = nil
    tree_popup = nil
    preview_popup = nil
    tree_nodes = nil
    display_nodes = nil
    flat_nodes = nil
    scan_result = nil
    current_filter = nil
    cursor_line = 1
    current_view = "browser"
    security.reset()
    settings_view.reset()
    observability.reset()
    ralph.reset()
  end
end

function M.is_open()
  return layout ~= nil
end

-- ---------------------------------------------------------------------------
-- Rendering (view-aware)
-- ---------------------------------------------------------------------------

function M._render_tree()
  if current_view == "security" then
    M._render_security_list()
  elseif current_view == "settings" then
    M._render_settings_list()
  elseif current_view == "observability" then
    M._render_observability_list()
  elseif current_view == "ralph" then
    M._render_ralph_list()
  else
    M._render_browser_tree()
  end
end

function M._render_browser_tree()
  flat_nodes = tree_mod.flatten(display_nodes)
  local width = config.options.tree_width - 2 -- account for border
  local lines, highlights = tree_mod.render(flat_nodes, width)

  vim.api.nvim_buf_set_option(tree_popup.bufnr, "modifiable", true)
  vim.api.nvim_buf_set_lines(tree_popup.bufnr, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(tree_popup.bufnr, "modifiable", false)

  -- Apply highlights
  local ns = vim.api.nvim_create_namespace("prp_browser_tree")
  vim.api.nvim_buf_clear_namespace(tree_popup.bufnr, ns, 0, -1)
  for _, hl in ipairs(highlights) do
    pcall(vim.api.nvim_buf_add_highlight, tree_popup.bufnr, ns, hl.group, hl.line - 1, hl.col_start, hl.col_end)
  end

  M._render_status()
end

function M._render_security_list()
  local width = config.options.tree_width - 2
  local lines, highlights = security.render_list(width)

  vim.api.nvim_buf_set_option(tree_popup.bufnr, "modifiable", true)
  vim.api.nvim_buf_set_lines(tree_popup.bufnr, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(tree_popup.bufnr, "modifiable", false)

  local ns = vim.api.nvim_create_namespace("prp_browser_tree")
  vim.api.nvim_buf_clear_namespace(tree_popup.bufnr, ns, 0, -1)
  for _, hl in ipairs(highlights) do
    pcall(vim.api.nvim_buf_add_highlight, tree_popup.bufnr, ns, hl.group, hl.line - 1, hl.col_start or 0, hl.col_end or -1)
  end

  M._render_security_status()
end

function M._render_settings_list()
  local width = config.options.tree_width - 2
  local lines, highlights = settings_view.render_list(width)

  vim.api.nvim_buf_set_option(tree_popup.bufnr, "modifiable", true)
  vim.api.nvim_buf_set_lines(tree_popup.bufnr, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(tree_popup.bufnr, "modifiable", false)

  local ns = vim.api.nvim_create_namespace("prp_browser_tree")
  vim.api.nvim_buf_clear_namespace(tree_popup.bufnr, ns, 0, -1)
  for _, hl in ipairs(highlights) do
    pcall(vim.api.nvim_buf_add_highlight, tree_popup.bufnr, ns, hl.group, hl.line - 1, hl.col_start or 0, hl.col_end or -1)
  end

  M._render_settings_status()
end

function M._render_observability_list()
  local width = config.options.tree_width - 2
  local lines, highlights = observability.render_list(width)

  vim.api.nvim_buf_set_option(tree_popup.bufnr, "modifiable", true)
  vim.api.nvim_buf_set_lines(tree_popup.bufnr, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(tree_popup.bufnr, "modifiable", false)

  local ns = vim.api.nvim_create_namespace("prp_browser_tree")
  vim.api.nvim_buf_clear_namespace(tree_popup.bufnr, ns, 0, -1)
  for _, hl in ipairs(highlights) do
    pcall(vim.api.nvim_buf_add_highlight, tree_popup.bufnr, ns, hl.group, hl.line - 1, hl.col_start or 0, hl.col_end or -1)
  end

  M._render_observability_status()
end

function M._render_observability_status()
  if not tree_popup or not tree_popup.bufnr then return end
  local status = "[r]refresh [S]start [X]stop [d]dashboard [b]back [?]help"
  if observability.is_busy() then
    status = "Starting/stopping..."
  end
  if tree_popup.border then
    tree_popup.border:set_text("bottom", " " .. status .. " ", "center")
  end
end

function M._render_ralph_list()
  local width = config.options.tree_width - 2
  local lines, highlights = ralph.render_list(width)

  vim.api.nvim_buf_set_option(tree_popup.bufnr, "modifiable", true)
  vim.api.nvim_buf_set_lines(tree_popup.bufnr, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(tree_popup.bufnr, "modifiable", false)

  local ns = vim.api.nvim_create_namespace("prp_browser_tree")
  vim.api.nvim_buf_clear_namespace(tree_popup.bufnr, ns, 0, -1)
  for _, hl in ipairs(highlights) do
    pcall(vim.api.nvim_buf_add_highlight, tree_popup.bufnr, ns, hl.group, hl.line - 1, hl.col_start or 0, hl.col_end or -1)
  end

  M._render_ralph_status()
end

function M._render_ralph_status()
  if not tree_popup or not tree_popup.bufnr then return end
  local status = "[r]reload [b]back [?]help"
  if tree_popup.border then
    tree_popup.border:set_text("bottom", " " .. status .. " ", "center")
  end
end

function M._render_settings_status()
  if not tree_popup or not tree_popup.bufnr then return end
  local status = "[w]save [r]refresh [p]project [t]state [b]back [?]help"
  if tree_popup.border then
    tree_popup.border:set_text("bottom", " " .. status .. " ", "center")
  end
end

function M._render_status()
  if not tree_popup or not tree_popup.bufnr then
    return
  end

  if current_view == "security" then
    M._render_security_status()
    return
  end

  if current_view == "settings" then
    M._render_settings_status()
    return
  end

  if current_view == "observability" then
    M._render_observability_status()
    return
  end

  if current_view == "ralph" then
    M._render_ralph_status()
    return
  end

  local total = 0
  if scan_result then
    for _, cat in ipairs(scan_result.categories) do
      total = total + cat.count
    end
  end

  local status = total .. " files"
  if current_filter and current_filter ~= "" then
    local filtered_count = 0
    for _, node in ipairs(flat_nodes) do
      if not node.is_category then
        filtered_count = filtered_count + 1
      end
    end
    status = filtered_count .. "/" .. total .. " (filter: " .. current_filter .. ")"
  end

  if tree_popup.border then
    tree_popup.border:set_text("bottom", " " .. status .. " ", "center")
  end
end

function M._render_security_status()
  if not tree_popup or not tree_popup.bufnr then
    return
  end

  local status = "[S]can [b]ack [1-4]filter [a]ll [q]uit"
  if security.is_scanning() then
    status = "Scanning..."
  end

  if tree_popup.border then
    tree_popup.border:set_text("bottom", " " .. status .. " ", "center")
  end
end

-- ---------------------------------------------------------------------------
-- Preview (view-aware)
-- ---------------------------------------------------------------------------

function M._update_preview()
  if not preview_popup then
    return
  end

  if current_view == "security" then
    M._update_security_preview()
  elseif current_view == "settings" then
    M._update_settings_preview()
  elseif current_view == "observability" then
    M._update_observability_preview()
  elseif current_view == "ralph" then
    M._update_ralph_preview()
  else
    M._update_browser_preview()
  end
end

function M._update_browser_preview()
  if not flat_nodes then
    return
  end

  local node = flat_nodes[cursor_line]
  if not node then
    return
  end

  if node.is_category then
    -- Show category info
    local info = node.category_info or {}
    local lines = {
      "",
      " " .. (info.icon or "") .. " " .. node.text,
      " " .. string.rep("─", 40),
      "",
      " " .. (info.description or ""),
      "",
      " Items: " .. (node.children and #node.children or 0),
      "",
      " Press Enter to expand",
    }
    vim.api.nvim_buf_set_option(preview_popup.bufnr, "modifiable", true)
    vim.api.nvim_buf_set_lines(preview_popup.bufnr, 0, -1, false, lines)
    vim.api.nvim_buf_set_option(preview_popup.bufnr, "modifiable", false)

    -- Update preview title
    if preview_popup.border then
      preview_popup.border:set_text("top", " " .. node.text .. " ", "center")
    end
  elseif node.item then
    -- Update preview title
    if preview_popup.border then
      preview_popup.border:set_text("top", " " .. node.item.name .. " ", "center")
    end
    preview.render(node.item, preview_popup.bufnr)
  end
end

function M._update_security_preview()
  local idx = security.display_index_from_cursor(cursor_line)
  local finding = security.get_finding_at(idx)

  if finding then
    if preview_popup.border then
      preview_popup.border:set_text("top", " Finding Detail ", "center")
    end
    security.render_preview(finding, preview_popup.bufnr)
  else
    if preview_popup.border then
      preview_popup.border:set_text("top", " Finding Detail ", "center")
    end
    local lines = { "", "  Select a finding to see details" }
    vim.api.nvim_buf_set_option(preview_popup.bufnr, "modifiable", true)
    vim.api.nvim_buf_set_lines(preview_popup.bufnr, 0, -1, false, lines)
    vim.api.nvim_buf_set_option(preview_popup.bufnr, "modifiable", false)
  end
end

function M._update_settings_preview()
  local idx   = settings_view.display_index_from_cursor(cursor_line)
  local entry = settings_view.get_entry_at(idx)

  if preview_popup.border then
    preview_popup.border:set_text("top", " Settings Detail ", "center")
  end
  settings_view.render_preview(entry, preview_popup.bufnr)
end

function M._update_observability_preview()
  local idx = observability.display_index_from_cursor(cursor_line)
  local ev = observability.get_event_at(idx)

  if preview_popup.border then
    preview_popup.border:set_text("top", " Event Detail ", "center")
  end
  observability.render_preview(ev, preview_popup.bufnr)
end

function M._update_ralph_preview()
  local idx = ralph.display_index_from_cursor(cursor_line)
  local entry = ralph.get_entry_at(idx)
  local root = config.options.root_path

  if preview_popup.border then
    preview_popup.border:set_text("top", " Ralph Detail ", "center")
  end
  ralph.render_preview(entry, preview_popup.bufnr, root)
end

-- ---------------------------------------------------------------------------
-- View switching
-- ---------------------------------------------------------------------------

function M._switch_to_settings()
  current_view = "settings"

  if tree_popup.border then
    tree_popup.border:set_text("top", " PRP Settings ", "center")
  end
  if preview_popup.border then
    preview_popup.border:set_text("top", " Settings Detail ", "center")
  end

  settings_view.load_settings()
  M._render_tree()
  cursor_line = 1
  pcall(vim.api.nvim_win_set_cursor, tree_popup.winid, { 1, 0 })
  M._update_preview()
  M._setup_keymaps()
end

function M._switch_to_security()
  current_view = "security"
  current_filter = nil

  if tree_popup.border then
    tree_popup.border:set_text("top", " Security Scan ", "center")
  end

  -- If no report data yet, trigger a scan immediately
  if not security.get_report() then
    M._trigger_security_scan()
  else
    M._render_tree()
    cursor_line = 1
    pcall(vim.api.nvim_win_set_cursor, tree_popup.winid, { 1, 0 })
    M._update_preview()
  end

  M._setup_keymaps()
end

function M._switch_to_observability()
  current_view = "observability"

  if tree_popup.border then
    tree_popup.border:set_text("top", " Observability ", "center")
  end
  if preview_popup.border then
    preview_popup.border:set_text("top", " Event Detail ", "center")
  end

  -- Check health and fetch events
  observability.check_health(function(ok)
    if not layout then return end
    if ok then
      observability.fetch_events(function()
        if not layout then return end
        M._render_tree()
        cursor_line = 1
        pcall(vim.api.nvim_win_set_cursor, tree_popup.winid, { 1, 0 })
        M._update_preview()
      end)
    else
      M._render_tree()
      cursor_line = 1
      pcall(vim.api.nvim_win_set_cursor, tree_popup.winid, { 1, 0 })
      M._update_preview()
    end
  end)

  M._render_tree()
  cursor_line = 1
  pcall(vim.api.nvim_win_set_cursor, tree_popup.winid, { 1, 0 })
  M._setup_keymaps()
end

function M._switch_to_ralph()
  current_view = "ralph"

  if tree_popup.border then
    tree_popup.border:set_text("top", " Ralph Loop ", "center")
  end
  if preview_popup.border then
    preview_popup.border:set_text("top", " Ralph Detail ", "center")
  end

  local root = config.options.root_path
  ralph.load_data(root)
  M._render_tree()
  cursor_line = 1
  pcall(vim.api.nvim_win_set_cursor, tree_popup.winid, { 1, 0 })
  M._update_preview()
  M._setup_keymaps()
end

function M._switch_to_browser()
  current_view = "browser"
  current_filter = nil
  security.clear_filter()

  if tree_popup.border then
    tree_popup.border:set_text("top", " PRP Browser ", "center")
  end

  M._render_tree()
  cursor_line = 1
  pcall(vim.api.nvim_win_set_cursor, tree_popup.winid, { 1, 0 })
  M._update_preview()
  M._setup_keymaps()
end

function M._trigger_security_scan()
  local root = config.options.root_path
  if not root then
    vim.notify("No root_path configured", vim.log.levels.ERROR)
    return
  end

  -- Show scanning state
  vim.api.nvim_buf_set_option(tree_popup.bufnr, "modifiable", true)
  vim.api.nvim_buf_set_lines(tree_popup.bufnr, 0, -1, false, {
    "",
    "  Scanning...",
    "",
    "  Running claude-secure on",
    "  " .. root,
  })
  vim.api.nvim_buf_set_option(tree_popup.bufnr, "modifiable", false)
  M._render_security_status()

  security.run_scan(root, function(success, err)
    if not layout then return end -- closed while scanning

    if success then
      M._render_tree()
      cursor_line = 1
      pcall(vim.api.nvim_win_set_cursor, tree_popup.winid, { 1, 0 })
      M._update_preview()
    else
      vim.notify("Security scan failed: " .. (err or "unknown"), vim.log.levels.ERROR)
      vim.api.nvim_buf_set_option(tree_popup.bufnr, "modifiable", true)
      vim.api.nvim_buf_set_lines(tree_popup.bufnr, 0, -1, false, {
        "",
        "  Scan failed",
        "  " .. (err or ""),
        "",
        "  Press S to retry",
      })
      vim.api.nvim_buf_set_option(tree_popup.bufnr, "modifiable", false)
    end
    M._render_security_status()
  end)
end

-- ---------------------------------------------------------------------------
-- Keymaps (view-aware)
-- ---------------------------------------------------------------------------

function M._setup_keymaps()
  local tree_buf = tree_popup.bufnr

  -- Clear existing keymaps by overwriting
  local function map(key, fn)
    vim.keymap.set("n", key, fn, { buffer = tree_buf, noremap = true, silent = true })
  end

  -- Shared keymaps
  map("q", M.close)

  -- Scroll preview from tree panel
  map("<C-d>", function()
    if preview_popup and preview_popup.winid then
      pcall(vim.api.nvim_win_call, preview_popup.winid, function()
        vim.cmd("normal! \\<C-d>")
      end)
    end
  end)

  map("<C-u>", function()
    if preview_popup and preview_popup.winid then
      pcall(vim.api.nvim_win_call, preview_popup.winid, function()
        vim.cmd("normal! \\<C-u>")
      end)
    end
  end)

  if current_view == "security" then
    M._setup_security_keymaps(map)
  elseif current_view == "settings" then
    M._setup_settings_keymaps(map)
  elseif current_view == "observability" then
    M._setup_observability_keymaps(map)
  elseif current_view == "ralph" then
    M._setup_ralph_keymaps(map)
  else
    M._setup_browser_keymaps(map)
  end
end

function M._setup_browser_keymaps(map)
  map("<Esc>", function()
    if current_filter and current_filter ~= "" then
      current_filter = nil
      display_nodes = tree_nodes
      M._render_tree()
      pcall(vim.api.nvim_win_set_cursor, tree_popup.winid, { 1, 0 })
      cursor_line = 1
      M._update_preview()
    else
      M.close()
    end
  end)

  -- Expand / select
  map("<CR>", function()
    local node = flat_nodes[cursor_line]
    if not node then return end
    if node.is_category then
      tree_mod.toggle_expand(node)
      M._render_tree()
      pcall(vim.api.nvim_win_set_cursor, tree_popup.winid, { cursor_line, 0 })
      M._update_preview()
    end
  end)

  map("l", function()
    local node = flat_nodes[cursor_line]
    if not node then return end
    if node.is_category and not node.expanded then
      tree_mod.toggle_expand(node)
      M._render_tree()
      pcall(vim.api.nvim_win_set_cursor, tree_popup.winid, { cursor_line, 0 })
      M._update_preview()
    elseif node.is_category and node.expanded then
      if node.children and #node.children > 0 then
        pcall(vim.api.nvim_win_set_cursor, tree_popup.winid, { cursor_line + 1, 0 })
      end
    end
  end)

  map("h", function()
    local node = flat_nodes[cursor_line]
    if not node then return end
    if node.is_category and node.expanded then
      tree_mod.toggle_expand(node)
      M._render_tree()
      pcall(vim.api.nvim_win_set_cursor, tree_popup.winid, { cursor_line, 0 })
      M._update_preview()
    elseif not node.is_category then
      for i = cursor_line - 1, 1, -1 do
        if flat_nodes[i] and flat_nodes[i].is_category then
          pcall(vim.api.nvim_win_set_cursor, tree_popup.winid, { i, 0 })
          break
        end
      end
    end
  end)

  map("e", function()
    local node = flat_nodes[cursor_line]
    if node and node.item then
      actions.export_item(node.item)
    end
  end)

  map("E", function()
    local node = flat_nodes[cursor_line]
    if not node then return end
    local cat_node = nil
    if node.is_category then
      cat_node = node
    else
      for i = cursor_line - 1, 1, -1 do
        if flat_nodes[i] and flat_nodes[i].is_category then
          cat_node = flat_nodes[i]
          break
        end
      end
    end
    if cat_node and cat_node.children then
      local items = {}
      for _, child in ipairs(cat_node.children) do
        if child.item then table.insert(items, child.item) end
      end
      actions.export_category(cat_node.text, items, config.options.root_path)
    end
  end)

  map("y", function()
    local node = flat_nodes[cursor_line]
    if node and node.item then
      actions.yank_path(node.item)
    end
  end)

  map("/", function()
    actions.search(function(query)
      current_filter = query
      if query == "" then
        display_nodes = tree_nodes
      else
        display_nodes = tree_mod.filter(tree_nodes, query)
      end
      M._render_tree()
      cursor_line = 1
      pcall(vim.api.nvim_win_set_cursor, tree_popup.winid, { 1, 0 })
      M._update_preview()
    end)
  end)

  map("?", function()
    actions.show_help(tree_popup.winid)
  end)

  -- Switch to security view
  map("s", function()
    M._switch_to_security()
  end)

  -- Switch to settings view
  map("c", function()
    M._switch_to_settings()
  end)

  -- Switch to observability view
  map("o", function()
    M._switch_to_observability()
  end)

  -- Switch to ralph view
  map("R", function()
    M._switch_to_ralph()
  end)
end

function M._setup_security_keymaps(map)
  -- Back to browser
  map("b", function()
    M._switch_to_browser()
  end)

  map("<Esc>", function()
    M._switch_to_browser()
  end)

  -- Re-run scan
  map("S", function()
    M._trigger_security_scan()
  end)

  -- Open file at finding line
  map("<CR>", function()
    local idx = security.display_index_from_cursor(cursor_line)
    local finding = security.get_finding_at(idx)
    if finding and finding.file_path ~= "" then
      M.close()
      vim.cmd("edit " .. vim.fn.fnameescape(finding.file_path))
      if finding.line_number > 0 then
        pcall(vim.api.nvim_win_set_cursor, 0, { finding.line_number, 0 })
        vim.cmd("normal! zz")
      end
    end
  end)

  -- Severity filters: 1=CRITICAL, 2=HIGH, 3=MEDIUM, 4=LOW
  local sev_map = { "CRITICAL", "HIGH", "MEDIUM", "LOW" }
  for i, sev in ipairs(sev_map) do
    map(tostring(i), function()
      security.set_filter(sev)
      M._render_tree()
      cursor_line = 1
      pcall(vim.api.nvim_win_set_cursor, tree_popup.winid, { 1, 0 })
      M._update_preview()
    end)
  end

  -- Show all (clear filter)
  map("a", function()
    security.clear_filter()
    M._render_tree()
    cursor_line = 1
    pcall(vim.api.nvim_win_set_cursor, tree_popup.winid, { 1, 0 })
    M._update_preview()
  end)

  -- Help
  map("?", function()
    actions.show_security_help(tree_popup.winid)
  end)

  -- Disable browser-specific keys in security view
  for _, key in ipairs({ "l", "h", "e", "E", "y", "/", "c", "o" }) do
    map(key, function() end)
  end
end

function M._setup_settings_keymaps(map)
  -- Back to browser
  map("b", function()
    M._switch_to_browser()
  end)

  map("<Esc>", function()
    M._switch_to_browser()
  end)

  -- Edit selected field
  map("<CR>", function()
    local idx   = settings_view.display_index_from_cursor(cursor_line)
    local entry = settings_view.get_entry_at(idx)
    if not entry or entry.is_header then return end
    settings_view.edit_field(entry, function()
      M._render_tree()
      pcall(vim.api.nvim_win_set_cursor, tree_popup.winid, { cursor_line, 0 })
      M._update_preview()
    end)
  end)

  -- Pick Plane project from API
  map("p", function()
    settings_view.pick_plane_project(function(project_id)
      -- Write into the display entry for project_id
      local dl = settings_view.get_display_list()
      for _, entry in ipairs(dl) do
        if not entry.is_header and entry.section == "plane" and entry.key == "project_id" then
          settings_view._set_value("plane", "project_id", project_id)
          entry.value     = project_id
          entry.raw_value = project_id
          break
        end
      end
      M._render_tree()
      pcall(vim.api.nvim_win_set_cursor, tree_popup.winid, { cursor_line, 0 })
      M._update_preview()
    end)
  end)

  -- Pick Plane backlog state from API
  map("t", function()
    settings_view.pick_plane_state(function(state_id)
      local dl = settings_view.get_display_list()
      for _, entry in ipairs(dl) do
        if not entry.is_header and entry.section == "plane" and entry.key == "backlog_state_id" then
          settings_view._set_value("plane", "backlog_state_id", state_id)
          entry.value     = state_id
          entry.raw_value = state_id
          break
        end
      end
      M._render_tree()
      pcall(vim.api.nvim_win_set_cursor, tree_popup.winid, { cursor_line, 0 })
      M._update_preview()
    end)
  end)

  -- Save settings to disk
  map("w", function()
    settings_view.save_settings()
  end)

  -- Refresh Plane connection status
  map("r", function()
    settings_view.check_plane_connection(function(ok, err)
      if ok then
        vim.notify("Plane connection OK", vim.log.levels.INFO)
      else
        vim.notify("Plane connection failed: " .. (err or "unknown"), vim.log.levels.WARN)
      end
      M._render_tree()
      pcall(vim.api.nvim_win_set_cursor, tree_popup.winid, { cursor_line, 0 })
      M._update_preview()
    end)
  end)

  -- Help
  map("?", function()
    actions.show_settings_help(tree_popup.winid)
  end)

  -- Disable keys that don't apply in settings view
  for _, key in ipairs({ "s", "l", "h", "e", "E", "y", "/", "S", "1", "2", "3", "4", "a", "c", "o" }) do
    map(key, function() end)
  end
end

function M._setup_observability_keymaps(map)
  -- Back to browser
  map("b", function()
    M._switch_to_browser()
  end)

  map("<Esc>", function()
    M._switch_to_browser()
  end)

  -- Refresh: check health + fetch events
  map("r", function()
    observability.check_health(function(ok)
      if not layout then return end
      if ok then
        observability.fetch_events(function()
          if not layout then return end
          M._render_tree()
          pcall(vim.api.nvim_win_set_cursor, tree_popup.winid, { cursor_line, 0 })
          M._update_preview()
        end)
      else
        M._render_tree()
        pcall(vim.api.nvim_win_set_cursor, tree_popup.winid, { cursor_line, 0 })
        M._update_preview()
      end
      M._render_observability_status()
    end)
  end)

  -- Start server
  map("S", function()
    local root = config.options.root_path
    if not root then
      vim.notify("No root_path configured", vim.log.levels.ERROR)
      return
    end
    vim.notify("Starting observability server...", vim.log.levels.INFO)
    M._render_observability_status()
    observability.start_server(root, function(ok, msg)
      if not layout then return end
      if ok then
        vim.notify("Observability server started", vim.log.levels.INFO)
        -- Auto-refresh after start
        observability.check_health(function()
          if not layout then return end
          observability.fetch_events(function()
            if not layout then return end
            M._render_tree()
            pcall(vim.api.nvim_win_set_cursor, tree_popup.winid, { cursor_line, 0 })
            M._update_preview()
          end)
          M._render_tree()
          M._render_observability_status()
        end)
      else
        vim.notify("Failed to start server: " .. (msg or "unknown"), vim.log.levels.ERROR)
        M._render_observability_status()
      end
    end)
  end)

  -- Stop server
  map("X", function()
    local root = config.options.root_path
    if not root then return end
    vim.notify("Stopping observability server...", vim.log.levels.INFO)
    observability.stop_server(root, function(ok)
      if not layout then return end
      if ok then
        vim.notify("Observability server stopped", vim.log.levels.INFO)
      end
      observability.reset()
      observability.check_health(function()
        if not layout then return end
        M._render_tree()
        M._render_observability_status()
      end)
    end)
  end)

  -- Open dashboard in browser
  map("d", function()
    local url = "http://localhost:5173"
    if vim.fn.has("mac") == 1 then
      vim.fn.system({ "open", url })
    elseif vim.fn.has("unix") == 1 then
      vim.fn.system({ "xdg-open", url })
    end
    vim.notify("Opening dashboard: " .. url, vim.log.levels.INFO)
  end)

  -- Help
  map("?", function()
    actions.show_observability_help(tree_popup.winid)
  end)

  -- Disable keys that don't apply in observability view
  for _, key in ipairs({ "s", "c", "l", "h", "e", "E", "y", "/", "1", "2", "3", "4", "a", "o", "p", "t", "w", "R" }) do
    map(key, function() end)
  end
end

function M._setup_ralph_keymaps(map)
  -- Back to browser
  map("b", function()
    M._switch_to_browser()
  end)

  map("<Esc>", function()
    M._switch_to_browser()
  end)

  -- Reload ralph data
  map("r", function()
    local root = config.options.root_path
    ralph.load_data(root)
    M._render_tree()
    pcall(vim.api.nvim_win_set_cursor, tree_popup.winid, { cursor_line, 0 })
    M._update_preview()
    vim.notify("Ralph data reloaded", vim.log.levels.INFO)
  end)

  -- Open file under cursor in editor
  map("<CR>", function()
    local idx = ralph.display_index_from_cursor(cursor_line)
    local entry = ralph.get_entry_at(idx)
    if entry and entry.filename then
      local root = config.options.root_path
      local filepath = root .. "/ralph/" .. entry.filename
      if vim.fn.filereadable(filepath) == 1 then
        M.close()
        vim.cmd("edit " .. vim.fn.fnameescape(filepath))
      end
    end
  end)

  -- Help
  map("?", function()
    actions.show_ralph_help(tree_popup.winid)
  end)

  -- Disable keys that don't apply in ralph view
  for _, key in ipairs({ "s", "c", "l", "h", "e", "E", "y", "/", "S", "X", "d", "1", "2", "3", "4", "a", "o", "p", "t", "w", "R" }) do
    map(key, function() end)
  end
end

return M
