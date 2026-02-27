local M = {}

--- Setup the PRP browser plugin.
---@param opts table|nil  Configuration options
function M.setup(opts)
  local config = require("prp-browser.config")
  config.setup(opts)

  -- Define highlight groups with defaults (users can override via colorscheme)
  M._setup_highlights()
end

--- Open the PRP browser.
function M.open()
  local ui = require("prp-browser.ui")
  ui.open()
end

--- Close the PRP browser.
function M.close()
  local ui = require("prp-browser.ui")
  ui.close()
end

--- Toggle the PRP browser.
function M.toggle()
  local ui = require("prp-browser.ui")
  if ui.is_open() then
    ui.close()
  else
    ui.open()
  end
end

function M._setup_highlights()
  local highlights = {
    PRPBrowserCategory = { default = true, bold = true, fg = "#7aa2f7" },
    PRPBrowserCategoryEmpty = { default = true, bold = true, fg = "#565f89" },
    PRPBrowserItem = { default = true, fg = "#c0caf5" },
    PRPBrowserPreviewTitle = { default = true, bold = true, fg = "#bb9af7" },
    PRPBrowserMetaKey = { default = true, bold = true, fg = "#7dcfff" },
    PRPBrowserMetaValue = { default = true, fg = "#9ece6a" },
    -- Security view highlights
    PRPSecurityRiskCritical = { default = true, bold = true, fg = "#f7768e" },
    PRPSecurityRiskHigh = { default = true, bold = true, fg = "#ff9e64" },
    PRPSecurityRiskMedium = { default = true, bold = true, fg = "#e0af68" },
    PRPSecurityRiskLow = { default = true, bold = true, fg = "#9ece6a" },
    PRPSecuritySevCritical = { default = true, bold = true, fg = "#f7768e" },
    PRPSecuritySevHigh = { default = true, fg = "#ff9e64" },
    PRPSecuritySevMedium = { default = true, fg = "#e0af68" },
    PRPSecuritySevLow = { default = true, fg = "#9ece6a" },
    PRPSecurityItem = { default = true, fg = "#a9b1d6" },
    PRPSecurityHighlightLine = { default = true, bg = "#3b4261" },
    -- Settings view highlights
    PRPSettingsSection     = { default = true, bold = true, fg = "#7aa2f7" },
    PRPSettingsKey         = { default = true, bold = true, fg = "#7dcfff" },
    PRPSettingsValue       = { default = true, fg = "#9ece6a" },
    PRPSettingsConnected   = { default = true, bold = true, fg = "#9ece6a" },
    PRPSettingsDisconnected = { default = true, bold = true, fg = "#f7768e" },
  }

  for name, opts in pairs(highlights) do
    vim.api.nvim_set_hl(0, name, opts)
  end
end

return M
