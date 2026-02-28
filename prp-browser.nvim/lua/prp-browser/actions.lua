local M = {}

--- Export a single item to a destination directory.
---@param item table  -- ScanItem
function M.export_item(item)
  if not item then
    vim.notify("No item selected", vim.log.levels.WARN)
    return
  end

  vim.ui.input({ prompt = "Export to directory: ", completion = "dir" }, function(dest)
    if not dest or dest == "" then
      return
    end
    dest = vim.fn.expand(dest)

    -- Ensure destination exists
    vim.fn.mkdir(dest, "p")

    local target = dest .. "/" .. vim.fn.fnamemodify(item.path, ":t")
    local ok, err = M._copy_file(item.path, target)
    if ok then
      vim.notify("Exported: " .. target, vim.log.levels.INFO)
    else
      vim.notify("Export failed: " .. (err or "unknown error"), vim.log.levels.ERROR)
    end
  end)
end

--- Export all items in a category, preserving directory structure.
---@param category_name string
---@param items table[]  -- ScanItem[]
---@param root string
function M.export_category(category_name, items, root)
  if not items or #items == 0 then
    vim.notify("No items in category: " .. category_name, vim.log.levels.WARN)
    return
  end

  vim.ui.input({ prompt = "Export '" .. category_name .. "' to directory: ", completion = "dir" }, function(dest)
    if not dest or dest == "" then
      return
    end
    dest = vim.fn.expand(dest)

    local count = 0
    for _, item in ipairs(items) do
      local rel = item.rel_path
      local target = dest .. "/" .. rel
      local target_dir = vim.fn.fnamemodify(target, ":h")
      vim.fn.mkdir(target_dir, "p")

      local ok, _ = M._copy_file(item.path, target)
      if ok then
        count = count + 1
      end
    end

    vim.notify("Exported " .. count .. "/" .. #items .. " files to " .. dest, vim.log.levels.INFO)
  end)
end

--- Yank the relative path of an item to clipboard.
---@param item table  -- ScanItem
function M.yank_path(item)
  if not item then
    vim.notify("No item selected", vim.log.levels.WARN)
    return
  end

  vim.fn.setreg("+", item.rel_path)
  vim.fn.setreg('"', item.rel_path)
  vim.notify("Yanked: " .. item.rel_path, vim.log.levels.INFO)
end

--- Show help popup with keybinding reference.
---@param parent_winid number  -- parent window for positioning
function M.show_help(parent_winid)
  local Popup = require("nui.popup")

  local help_lines = {
    " PRP Browser — Keybindings",
    " " .. string.rep("─", 40),
    "",
    " Navigation",
    "   j / k        Move down / up",
    "   Enter / l    Expand category or select item",
    "   h            Collapse category",
    "",
    " Actions",
    "   e            Export selected item",
    "   E            Export entire category",
    "   y            Yank file path to clipboard",
    "   /            Filter items by name/description",
    "   Esc or /     Clear filter (when filtered)",
    "",
    " Views",
    "   s            Security scan view",
    "   c            Settings / config view",
    "   o            Observability dashboard view",
    "   R            Ralph autonomous loop view",
    "",
    " General",
    "   ?            Toggle this help",
    "   q / Esc      Close browser",
    "   Ctrl-d/u     Scroll preview",
    "",
    " " .. string.rep("─", 40),
    " Press any key to close this help",
  }

  local popup = Popup({
    position = "50%",
    size = {
      width = 48,
      height = #help_lines + 2,
    },
    enter = true,
    focusable = true,
    border = {
      style = "rounded",
      text = {
        top = " Help ",
        top_align = "center",
      },
    },
    buf_options = {
      modifiable = false,
      readonly = true,
    },
  })

  popup:mount()

  vim.api.nvim_set_option_value("modifiable", true, { buf = popup.bufnr })
  vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, help_lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = popup.bufnr })

  -- Highlight title
  local ns = vim.api.nvim_create_namespace("prp_browser_help")
  vim.api.nvim_buf_add_highlight(popup.bufnr, ns, "PRPBrowserCategory", 0, 0, -1)

  -- Close on any key
  local function close()
    popup:unmount()
  end

  -- Map common keys to close
  for _, key in ipairs({ "<Esc>", "q", "?", "<CR>", "<Space>" }) do
    popup:map("n", key, close, { noremap = true })
  end

  -- Also close on any unmapped key after a short delay
  vim.api.nvim_create_autocmd("BufLeave", {
    buffer = popup.bufnr,
    once = true,
    callback = close,
  })
end

--- Search/filter: prompt user for query string.
---@param callback fun(query: string)
function M.search(callback)
  vim.ui.input({ prompt = "Filter: " }, function(query)
    if query ~= nil then
      callback(query)
    end
  end)
end

--- Show security view help popup.
---@param parent_winid number
function M.show_security_help(parent_winid)
  local Popup = require("nui.popup")

  local help_lines = {
    " Security Scan — Keybindings",
    " " .. string.rep("─", 40),
    "",
    " Navigation",
    "   j / k        Move down / up",
    "   Enter        Open file at finding line",
    "",
    " Scan",
    "   S            Re-run security scan",
    "",
    " Filters",
    "   1            Show CRITICAL only",
    "   2            Show HIGH only",
    "   3            Show MEDIUM only",
    "   4            Show LOW only",
    "   a            Show all (clear filter)",
    "",
    " General",
    "   b / Esc      Back to browser view",
    "   ?            Toggle this help",
    "   q            Close browser",
    "   Ctrl-d/u     Scroll preview",
    "",
    " " .. string.rep("─", 40),
    " Press any key to close this help",
  }

  local popup = Popup({
    position = "50%",
    size = {
      width = 48,
      height = #help_lines + 2,
    },
    enter = true,
    focusable = true,
    border = {
      style = "rounded",
      text = {
        top = " Security Help ",
        top_align = "center",
      },
    },
    buf_options = {
      modifiable = false,
      readonly = true,
    },
  })

  popup:mount()

  vim.api.nvim_set_option_value("modifiable", true, { buf = popup.bufnr })
  vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, help_lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = popup.bufnr })

  local ns = vim.api.nvim_create_namespace("prp_browser_help")
  vim.api.nvim_buf_add_highlight(popup.bufnr, ns, "PRPBrowserCategory", 0, 0, -1)

  local function close()
    popup:unmount()
  end

  for _, key in ipairs({ "<Esc>", "q", "?", "<CR>", "<Space>" }) do
    popup:map("n", key, close, { noremap = true })
  end

  vim.api.nvim_create_autocmd("BufLeave", {
    buffer = popup.bufnr,
    once = true,
    callback = close,
  })
end

--- Show settings view help popup.
---@param parent_winid number
function M.show_settings_help(parent_winid)
  local Popup = require("nui.popup")

  local help_lines = {
    " Settings — Keybindings",
    " " .. string.rep("─", 40),
    "",
    " Navigation",
    "   j / k        Move down / up",
    "",
    " Editing",
    "   Enter        Edit selected field",
    "   p            Pick Plane project from API",
    "   t            Pick Plane backlog state from API",
    "   w            Save settings to disk",
    "   r            Refresh Plane connection status",
    "",
    " General",
    "   b / Esc      Back to browser view",
    "   ?            Toggle this help",
    "   q            Close browser",
    "   Ctrl-d/u     Scroll preview",
    "",
    " " .. string.rep("─", 40),
    " Press any key to close this help",
  }

  local popup = Popup({
    position = "50%",
    size = {
      width = 48,
      height = #help_lines + 2,
    },
    enter = true,
    focusable = true,
    border = {
      style = "rounded",
      text = {
        top = " Settings Help ",
        top_align = "center",
      },
    },
    buf_options = {
      modifiable = false,
      readonly = true,
    },
  })

  popup:mount()

  vim.api.nvim_set_option_value("modifiable", true, { buf = popup.bufnr })
  vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, help_lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = popup.bufnr })

  local ns = vim.api.nvim_create_namespace("prp_browser_help")
  vim.api.nvim_buf_add_highlight(popup.bufnr, ns, "PRPSettingsSection", 0, 0, -1)

  local function close()
    popup:unmount()
  end

  for _, key in ipairs({ "<Esc>", "q", "?", "<CR>", "<Space>" }) do
    popup:map("n", key, close, { noremap = true })
  end

  vim.api.nvim_create_autocmd("BufLeave", {
    buffer = popup.bufnr,
    once = true,
    callback = close,
  })
end

function M.show_observability_help(parent_winid)
  local Popup = require("nui.popup")

  local help_lines = {
    " Observability — Keybindings",
    " " .. string.rep("─", 40),
    "",
    " Navigation",
    "   j / k        Move down / up",
    "",
    " Actions",
    "   r            Refresh server status + events",
    "   S            Start observability server",
    "   X            Stop observability server",
    "   d            Open dashboard in browser",
    "",
    " General",
    "   b / Esc      Back to browser view",
    "   ?            Toggle this help",
    "   q            Close browser",
    "   Ctrl-d/u     Scroll preview",
    "",
    " " .. string.rep("─", 40),
    " Press any key to close this help",
  }

  local popup = Popup({
    position = "50%",
    size = {
      width = 48,
      height = #help_lines + 2,
    },
    enter = true,
    focusable = true,
    border = {
      style = "rounded",
      text = {
        top = " Observability Help ",
        top_align = "center",
      },
    },
    buf_options = {
      modifiable = false,
      readonly = true,
    },
  })

  popup:mount()

  vim.api.nvim_set_option_value("modifiable", true, { buf = popup.bufnr })
  vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, help_lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = popup.bufnr })

  local ns = vim.api.nvim_create_namespace("prp_browser_help")
  vim.api.nvim_buf_add_highlight(popup.bufnr, ns, "PRPSettingsSection", 0, 0, -1)

  local function close()
    popup:unmount()
  end

  for _, key in ipairs({ "<Esc>", "q", "?", "<CR>", "<Space>" }) do
    popup:map("n", key, close, { noremap = true })
  end

  vim.api.nvim_create_autocmd("BufLeave", {
    buffer = popup.bufnr,
    once = true,
    callback = close,
  })
end

function M.show_ralph_help(parent_winid)
  local Popup = require("nui.popup")

  local help_lines = {
    " Ralph Loop — Keybindings",
    " " .. string.rep("─", 40),
    "",
    " Navigation",
    "   j / k        Move down / up",
    "",
    " Actions",
    "   Enter        Open selected file in editor",
    "   r            Reload Ralph data",
    "",
    " General",
    "   b / Esc      Back to browser view",
    "   ?            Toggle this help",
    "   q            Close browser",
    "   Ctrl-d/u     Scroll preview",
    "",
    " " .. string.rep("─", 40),
    " Press any key to close this help",
  }

  local popup = Popup({
    position = "50%",
    size = {
      width = 48,
      height = #help_lines + 2,
    },
    enter = true,
    focusable = true,
    border = {
      style = "rounded",
      text = {
        top = " Ralph Help ",
        top_align = "center",
      },
    },
    buf_options = {
      modifiable = false,
      readonly = true,
    },
  })

  popup:mount()

  vim.api.nvim_set_option_value("modifiable", true, { buf = popup.bufnr })
  vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, help_lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = popup.bufnr })

  local ns = vim.api.nvim_create_namespace("prp_browser_help")
  vim.api.nvim_buf_add_highlight(popup.bufnr, ns, "PRPSettingsSection", 0, 0, -1)

  local function close()
    popup:unmount()
  end

  for _, key in ipairs({ "<Esc>", "q", "?", "<CR>", "<Space>" }) do
    popup:map("n", key, close, { noremap = true })
  end

  vim.api.nvim_create_autocmd("BufLeave", {
    buffer = popup.bufnr,
    once = true,
    callback = close,
  })
end

function M._copy_file(src, dst)
  local content = io.open(src, "rb")
  if not content then
    return false, "cannot read source"
  end
  local data = content:read("*a")
  content:close()

  local out = io.open(dst, "wb")
  if not out then
    return false, "cannot write destination"
  end
  out:write(data)
  out:close()
  return true, nil
end

return M
