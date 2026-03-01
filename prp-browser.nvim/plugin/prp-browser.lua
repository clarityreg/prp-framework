if vim.g.loaded_prp_browser then
  return
end
vim.g.loaded_prp_browser = true

vim.api.nvim_create_user_command("PRPBrowser", function()
  require("prp-browser").toggle()
end, {
  desc = "Toggle PRP Framework Browser",
})
