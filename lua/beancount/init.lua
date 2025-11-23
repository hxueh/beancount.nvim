-- Main module for the Beancount Neovim extension
-- Handles setup and initialization of all beancount features
local M = {}

local config = require("beancount.config")
local diagnostics = require("beancount.diagnostics")
local completion = require("beancount.completion")
local formatter = require("beancount.formatter")
local snippets = require("beancount.snippets")
local navigation = require("beancount.navigation")
local inlay_hints = require("beancount.inlay_hints")
local symbols = require("beancount.symbols")
local autofill = require("beancount.autofill")

-- Setup function to initialize the beancount extension
-- @param opts table: Configuration options (optional)
M.setup = function(opts)
  config.setup(opts or {})

  -- Initialize all beancount components with their respective configurations
  diagnostics.setup()
  completion.setup()
  formatter.setup()
  snippets.setup()
  navigation.setup()
  inlay_hints.setup()
  symbols.setup()
  autofill.setup()

  -- Set up autocommands to automatically configure beancount files when opened
  local augroup = vim.api.nvim_create_augroup("BeancountExtension", { clear = true })

  -- Auto-setup buffer when opening beancount files
  vim.api.nvim_create_autocmd("FileType", {
    group = augroup,
    pattern = "beancount",
    callback = function()
      M.setup_buffer()
    end,
  })

  -- Refresh diagnostics after saving beancount files
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = augroup,
    pattern = { "*.beancount", "*.bean", "*.beancount.oneline", "*.bean.oneline" },
    callback = function()
      diagnostics.refresh()
    end,
  })
end

-- Setup buffer-specific configurations for beancount files
-- Configures completion, formatting, navigation, and other features
M.setup_buffer = function()
  local buf = vim.api.nvim_get_current_buf()

  -- Prevent duplicate setup on the same buffer
  if vim.b[buf].beancount_setup then
    return
  end
  vim.b[buf].beancount_setup = true

  -- Configure buffer options specific to beancount syntax
  vim.bo[buf].commentstring = ";; %s"

  -- Initialize all buffer-specific features for beancount editing
  completion.setup_buffer(buf)
  completion.setup_hover(buf)
  formatter.setup_buffer(buf)
  navigation.setup_buffer(buf)
  inlay_hints.setup_buffer(buf)
  symbols.setup_buffer(buf)
  autofill.setup_buffer(buf)

  -- Run initial diagnostics check after a short delay to ensure buffer is ready
  vim.defer_fn(function()
    diagnostics.check_file()
  end, 100)
end

return M
