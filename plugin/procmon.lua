-- Auto-initialize with defaults. Users can re-call require("procmon").setup{...}.
if vim.g.loaded_procmon then
  return
end
vim.g.loaded_procmon = true

require("procmon").setup({})
