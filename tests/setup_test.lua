-- Exercise default setup using real buffers and files, including cross-cwd use.
vim.opt.runtimepath:prepend(vim.fn.getcwd())
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
  plugin.setup_buffer()
  assert(plugin.initialized and vim.b.beancount_setup, "initialize without setup call")
  assert(config.get("auto_fill_amounts"), "preserve config set before automatic setup")
  local count = #vim.api.nvim_get_autocmds({ group = "BeancountExtension" })
  plugin.setup_buffer()
  assert(#vim.api.nvim_get_autocmds({ group = "BeancountExtension" }) == count)
  vim.cmd("enew")
  vim.bo.filetype = "beancount"
  vim.b.beancount_setup = nil
  plugin.setup({ auto_fill_amounts = true })
  assert(vim.b.beancount_setup, "attach to an already open buffer")
end)
vim.fn.delete(root, "rf")
if not ok then
  print(err)
  vim.cmd("cquit 1")
end
print("Default setup and integration tests passed")
vim.cmd("qa!")
