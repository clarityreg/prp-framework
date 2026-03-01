local M = {}

---@class TreeNode
---@field id string
---@field text string
---@field is_category boolean
---@field expanded boolean
---@field children TreeNode[]|nil
---@field item table|nil  -- ScanItem for leaf nodes
---@field category_info table|nil  -- category metadata for category nodes
---@field depth number

--- Build tree from scanner output.
---@param scan_result table
---@return TreeNode[]
function M.build(scan_result)
  local nodes = {}
  for _, cat in ipairs(scan_result.categories) do
    local children = {}
    local items = scan_result.items[cat.name] or {}
    for _, item in ipairs(items) do
      table.insert(children, {
        id = item.rel_path,
        text = item.name,
        is_category = false,
        expanded = false,
        children = nil,
        item = item,
        depth = 1,
      })
    end

    table.insert(nodes, {
      id = "cat:" .. cat.name,
      text = cat.name,
      is_category = true,
      expanded = false,
      children = children,
      item = nil,
      category_info = cat,
      depth = 0,
    })
  end
  return nodes
end

--- Flatten expanded tree into a display list.
---@param nodes TreeNode[]
---@return TreeNode[]
function M.flatten(nodes)
  local flat = {}
  for _, node in ipairs(nodes) do
    table.insert(flat, node)
    if node.is_category and node.expanded and node.children then
      for _, child in ipairs(node.children) do
        table.insert(flat, child)
      end
    end
  end
  return flat
end

--- Toggle expand/collapse for a category node.
---@param node TreeNode
function M.toggle_expand(node)
  if node.is_category then
    node.expanded = not node.expanded
  end
end

--- Render a flat list of nodes into display lines and highlights.
---@param flat_nodes TreeNode[]
---@param width number
---@return string[] lines
---@return table[] highlights  -- { line, col_start, col_end, group }
function M.render(flat_nodes, width)
  local lines = {}
  local highlights = {}

  for i, node in ipairs(flat_nodes) do
    local line
    if node.is_category then
      local arrow = node.expanded and "▼" or "▸"
      local count = node.children and #node.children or 0
      local count_str = count > 0 and (" (" .. count .. ")") or " (empty)"
      line = arrow .. " " .. node.text .. count_str

      table.insert(highlights, {
        line = i,
        col_start = 0,
        col_end = #line,
        group = count > 0 and "PRPBrowserCategory" or "PRPBrowserCategoryEmpty",
      })
    else
      local prefix = "  "
      line = prefix .. node.text

      table.insert(highlights, {
        line = i,
        col_start = 0,
        col_end = #line,
        group = "PRPBrowserItem",
      })
    end

    -- Pad or truncate to width
    if #line > width then
      line = line:sub(1, width - 1) .. "…"
    end
    table.insert(lines, line)
  end

  return lines, highlights
end

--- Filter nodes by a search query. Returns a new tree with only matching items.
---@param nodes TreeNode[]
---@param query string
---@return TreeNode[]
function M.filter(nodes, query)
  if not query or query == "" then
    return nodes
  end

  local q = query:lower()
  local filtered = {}

  for _, cat_node in ipairs(nodes) do
    if cat_node.is_category and cat_node.children then
      local matching_children = {}
      for _, child in ipairs(cat_node.children) do
        local name_match = child.text:lower():find(q, 1, true)
        local desc_match = child.item and child.item.description and child.item.description:lower():find(q, 1, true)
        if name_match or desc_match then
          table.insert(matching_children, vim.tbl_extend("force", {}, child))
        end
      end

      if #matching_children > 0 then
        local cat_copy = vim.tbl_extend("force", {}, cat_node)
        cat_copy.children = matching_children
        cat_copy.expanded = true
        table.insert(filtered, cat_copy)
      end
    end
  end

  return filtered
end

return M
