local utils = require("prp-browser.utils")

local M = {}

local MAX_PREVIEW_LINES = 500

--- Render preview content for a scan item.
---@param item table  -- ScanItem
---@param buf number  -- buffer handle
function M.render(item, buf)
  if not item then
    M._set_lines(buf, { "", "  Select an item to preview" })
    return
  end

  local content = utils.read_file(item.path)
  if not content then
    M._set_lines(buf, { "", "  Could not read file: " .. item.path })
    return
  end

  local lines = {}
  local hl_marks = {}

  -- Header: metadata block
  table.insert(lines, " " .. item.name)
  table.insert(hl_marks, { line = 0, group = "PRPBrowserPreviewTitle" })

  table.insert(lines, " " .. string.rep("─", 50))
  table.insert(hl_marks, { line = 1, group = "Comment" })

  local header_line = 2

  -- Show relative path
  table.insert(lines, " Path: " .. item.rel_path)
  table.insert(hl_marks, { line = header_line, group = "PRPBrowserMetaKey", col_start = 1, col_end = 6 })
  header_line = header_line + 1

  -- Show filetype
  table.insert(lines, " Type: " .. item.filetype)
  table.insert(hl_marks, { line = header_line, group = "PRPBrowserMetaKey", col_start = 1, col_end = 6 })
  header_line = header_line + 1

  -- Show frontmatter metadata
  if item.metadata then
    for key, value in pairs(item.metadata) do
      local meta_line = " " .. key .. ": " .. value
      table.insert(lines, meta_line)
      table.insert(hl_marks, {
        line = header_line,
        group = "PRPBrowserMetaKey",
        col_start = 1,
        col_end = 1 + #key + 1,
      })
      table.insert(hl_marks, {
        line = header_line,
        group = "PRPBrowserMetaValue",
        col_start = 1 + #key + 2,
        col_end = #meta_line,
      })
      header_line = header_line + 1
    end
  end

  -- Show description if available (split on newlines for nvim_buf_set_lines)
  if item.description then
    table.insert(lines, "")
    header_line = header_line + 1
    local desc_lines = vim.split(item.description, "\n")
    for di, dl in ipairs(desc_lines) do
      table.insert(lines, " " .. dl)
      if di == 1 then
        table.insert(hl_marks, { line = header_line, group = "PRPBrowserMetaValue" })
      end
      header_line = header_line + 1
    end
  end

  table.insert(lines, "")
  table.insert(lines, " " .. string.rep("─", 50))
  header_line = header_line + 2

  -- File content
  local content_lines = vim.split(content, "\n")
  local truncated = false
  if #content_lines > MAX_PREVIEW_LINES then
    truncated = true
    content_lines = vim.list_slice(content_lines, 1, MAX_PREVIEW_LINES)
  end

  for _, cl in ipairs(content_lines) do
    table.insert(lines, cl)
  end

  if truncated then
    table.insert(lines, "")
    table.insert(lines, " ... (truncated at " .. MAX_PREVIEW_LINES .. " lines)")
  end

  M._set_lines(buf, lines)

  -- Apply header highlights
  local ns = vim.api.nvim_create_namespace("prp_browser_preview")
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

  for _, mark in ipairs(hl_marks) do
    local col_start = mark.col_start or 0
    local col_end = mark.col_end or -1
    pcall(vim.api.nvim_buf_add_highlight, buf, ns, mark.group, mark.line, col_start, col_end)
  end

  -- Apply treesitter syntax highlighting to the file body
  local ft = item.filetype
  if ft and ft ~= "" then
    -- Set a filetype-based syntax region for the content area
    vim.api.nvim_set_option_value("syntax", "", { buf = buf })
    local ok, parser_name = pcall(vim.treesitter.language.get_lang, ft)
    if not ok then
      parser_name = ft
    end

    -- Use a simpler approach: set filetype for syntax highlighting
    -- but preserve our custom namespace highlights
    pcall(function()
      vim.treesitter.start(buf, parser_name)
    end)
  end
end

function M._set_lines(buf, lines)
  vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
end

return M
