-- Exercise default setup using real buffers and files, including cross-cwd use.
vim.opt.runtimepath:prepend(vim.fn.getcwd())
-- Control initialization below instead of letting the ftplugin run during edit.
vim.cmd("filetype plugin off")
local root = vim.fn.tempname()
local config = require("beancount.config")
local utils = require("beancount.utils")
local function write(path, lines)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  vim.fn.writefile(lines or {}, path)
end
local ok, err = pcall(function()
  write(root .. "/ledger/.git")
  write(root .. "/ledger/main.bean", { 'include "books/month.bean"' })
  write(root .. "/ledger/books/month.bean", { "2026-01-01 open Assets:Bank USD" })
  write(root .. "/main.bean")
  write(root .. "/ledger/.venv/bin/python", { "#!/bin/sh", "exit 0" })
  vim.fn.setfperm(root .. "/ledger/.venv/bin/python", "rwx------")
  vim.cmd("edit " .. vim.fn.fnameescape(root .. "/ledger/books/month.bean"))
  vim.bo.filetype = "beancount"
  config.setup()
  assert(utils.get_main_bean_file() == root .. "/ledger/main.bean", "find ledger from included file")
  assert(utils.get_python_path() == root .. "/ledger/.venv/bin/python", "find ledger Python outside cwd")

  config.setup({ main_bean_file = "custom.bean", python_path = "custom-python" })
  assert(utils.get_main_bean_file() == vim.fn.getcwd() .. "/custom.bean", "preserve explicit relative main")
  assert(utils.get_python_path() == "custom-python", "preserve interpreter override")
  config.setup()
  vim.fn.delete(root .. "/ledger/main.bean")
  write(root .. "/ledger/main.beancount")
  assert(utils.get_main_bean_file() == root .. "/ledger/main.beancount", "detect long extension")
  vim.fn.delete(root .. "/ledger/main.beancount")
  assert(utils.get_main_bean_file() == root .. "/ledger/books/month.bean", "stop at Git boundary")
  vim.fn.delete(root .. "/ledger/.venv", "rf")
  local env = vim.env.VIRTUAL_ENV
  vim.env.VIRTUAL_ENV = root .. "/active"
  write(root .. "/active/bin/python", { "#!/bin/sh", "exit 0" })
  vim.fn.setfperm(root .. "/active/bin/python", "rwx------")
  assert(utils.get_python_path() == root .. "/active/bin/python", "use active virtualenv")
  vim.env.VIRTUAL_ENV = nil
  assert(utils.get_python_path() == (vim.fn.executable("python3") == 1 and "python3" or "python"))
  vim.env.VIRTUAL_ENV = env

  -- Stand in for Blink's public API to verify registration and user overrides.
  local providers, registrations = {}, 0
  package.loaded["blink.cmp.config"] = { sources = { providers = providers } }
  package.loaded["blink.cmp"] = {
    add_source_provider = function(id, provider)
      providers[id] = provider
    end,
    add_filetype_source = function(ft, id)
      assert(ft == "beancount" and id == "beancount")
      registrations = registrations + 1
    end,
  }
  local completion = require("beancount.completion")
  completion.setup()
  completion.setup()
  assert(registrations == 1, "register once")
  assert(providers.beancount.module == "beancount.completion.blink")
  providers.beancount.score_offset = 42
  completion.setup()
  assert(providers.beancount.score_offset == 42, "keep custom provider options")
  local source = require("beancount.completion.blink").new()
  assert(vim.tbl_contains(source:get_trigger_characters(), "#"))
  assert(source:enabled())
  vim.bo.filetype = "text"
  assert(not source:enabled(), "do not offer Beancount items in other filetypes")
  vim.bo.filetype = "beancount"

  -- Avoid background jobs here; diagnostics have their own end-to-end tests.
  require("beancount.diagnostics").check_file = function() end
  config.set("auto_fill_amounts", true)
  local plugin = require("beancount")
  -- Simulate an installed parser without depending on the user's Treesitter setup.
  local start = vim.treesitter.start
  local started = {}
  vim.treesitter.start = function(buf, language)
    assert(language == "beancount")
    started[buf] = (started[buf] or 0) + 1
  end
  plugin.setup_buffer()
  assert(started[vim.api.nvim_get_current_buf()] == 1, "start highlighting during automatic setup")
  assert(plugin.initialized and vim.b.beancount_setup, "initialize without setup call")
  assert(config.get("auto_fill_amounts"), "preserve config set before automatic setup")
  local count = #vim.api.nvim_get_autocmds({ group = "BeancountExtension" })
  plugin.setup_buffer()
  assert(started[vim.api.nvim_get_current_buf()] == 1, "do not start highlighting twice")
  assert(#vim.api.nvim_get_autocmds({ group = "BeancountExtension" }) == count)
  vim.api.nvim_set_current_buf(vim.api.nvim_create_buf(true, false))
  -- Mimic a FileType event that occurred before the plugin was loaded.
  vim.cmd("noautocmd setfiletype beancount")
  plugin.setup({ auto_fill_amounts = true })
  assert(vim.b.beancount_setup, "attach to an already open buffer")
  assert(started[vim.api.nvim_get_current_buf()] == 1, "start highlighting after lazy loading")

  -- FileType setup must also start highlighting for subsequently opened buffers.
  vim.api.nvim_set_current_buf(vim.api.nvim_create_buf(true, false))
  vim.bo.filetype = "beancount"
  assert(started[vim.api.nvim_get_current_buf()] == 1, "start highlighting on FileType")

  -- A missing parser or older Neovim API must not prevent other editor features.
  vim.treesitter.start = function() error("No parser for language beancount") end
  vim.api.nvim_set_current_buf(vim.api.nvim_create_buf(true, false))
  vim.bo.filetype = "beancount"
  assert(vim.b.beancount_setup, "set up without a parser")
  assert(#vim.api.nvim_get_autocmds({ buffer = 0, event = "InsertCharPre" }) > 0, "keep completion without a parser")
  vim.treesitter.start = nil
  vim.api.nvim_set_current_buf(vim.api.nvim_create_buf(true, false))
  vim.bo.filetype = "beancount"
  assert(vim.b.beancount_setup, "set up without the start API")
  assert(#vim.api.nvim_get_autocmds({ buffer = 0, event = "InsertCharPre" }) > 0, "keep completion without the start API")
  vim.treesitter.start = start
end)
vim.fn.delete(root, "rf")
if not ok then
  print(err)
  vim.cmd("cquit 1")
end
print("Default setup and integration tests passed")
vim.cmd("qa!")
