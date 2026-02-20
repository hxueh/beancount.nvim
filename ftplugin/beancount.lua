-- Beancount filetype plugin

-- Only load once
if vim.b.did_ftplugin then
  return
end
vim.b.did_ftplugin = 1

-- Set buffer options
vim.bo.commentstring = ";; %s"
vim.bo.comments = "b:;;"

-- Set folding options
vim.wo.foldmethod = "expr"
vim.wo.foldexpr = "v:lua.require('beancount.fold').foldexpr()"

-- Set formatoptions
vim.bo.formatoptions = vim.bo.formatoptions:gsub("[tca]", "") .. "qrn"

-- Buffer-specific key mappings
local opts = { buffer = true, silent = true }
local config = require("beancount.config")

-- Get configured keymaps or use defaults
local keymaps = config.get("keymaps") or {}

-- Formatting commands
if keymaps.format_transaction then
  vim.keymap.set("n", keymaps.format_transaction, function()
    require("beancount.formatter").format_transaction()
  end, vim.tbl_extend("force", opts, { desc = "Format current transaction" }))
end

-- Completion mappings
vim.keymap.set("i", "<C-x><C-o>", "<C-x><C-o>", opts)

-- Navigation commands
if keymaps.goto_definition then
  vim.keymap.set("n", keymaps.goto_definition, function()
    require("beancount.navigation").goto_definition()
  end, vim.tbl_extend("force", opts, { desc = "Go to definition" }))
end

if keymaps.next_transaction then
  vim.keymap.set("n", keymaps.next_transaction, function()
    require("beancount.navigation").next_transaction()
  end, vim.tbl_extend("force", opts, { desc = "Next transaction" }))
end

if keymaps.prev_transaction then
  vim.keymap.set("n", keymaps.prev_transaction, function()
    require("beancount.navigation").prev_transaction()
  end, vim.tbl_extend("force", opts, { desc = "Previous transaction" }))
end

-- Set up the buffer with beancount extension
require("beancount").setup_buffer()

-- Set the undo point for the plugin loading
vim.b.undo_ftplugin = "setl cms< com< fo< fdm< fde<"
