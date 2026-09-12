-- Verify observable navigation with real files, including an included file
-- outside the ledger directory. No filesystem-scan mocks encode old behavior.
vim.opt.runtimepath:prepend(vim.fn.getcwd())
local nav = require("beancount.navigation")
local diag = require("beancount.diagnostics")
local config = require("beancount.config")
local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/ledger", "p")
local main = root .. "/ledger/main.bean"
local definitions = root .. "/definitions with spaces.bean"
vim.fn.writefile({ '2020-01-01 open Assets:CashExtra', '2020-01-01 open Assets:Cash',
  '2020-01-01 open Assets:Épargne' }, definitions)
vim.fn.writefile({ 'include "../definitions with spaces.bean"', '2020-01-02 * "Example"',
  '  Assets:Cash 1 USD', '  Assets:Épargne -1 USD' }, main)
local ok, err = pcall(function()
  config.setup({ main_bean_file = main })
  vim.cmd("edit " .. vim.fn.fnameescape(main))
  vim.bo.filetype = "beancount"
  local output = vim.fn.system({ vim.env.BEANCOUNT_TEST_PYTHON, "pythonFiles/beancheck.py", main, "--json" })
  assert(diag.process_diagnostics(output))
  vim.api.nvim_win_set_cursor(0, { 3, 7 })
  nav.goto_definition()
  assert(vim.api.nvim_buf_get_name(0) == vim.loop.fs_realpath(definitions))
  assert(vim.fn.line(".") == 2, "exact account, not its prefix")
  vim.api.nvim_win_set_cursor(0, { 3, 27 })
  nav.goto_account_definition("Assets:Épargne")
  assert(vim.fn.line(".") == 3)
  nav.goto_account_definition("Assets:Cash")
  assert(vim.fn.line(".") == 2)
  vim.cmd("edit " .. vim.fn.fnameescape(main))
  nav.goto_include_file(vim.fn.getline(1))
  assert(vim.api.nvim_buf_get_name(0) == vim.loop.fs_realpath(definitions))
  vim.cmd("enew")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, {
    '2020/01/01 txn "One"', '  Assets:Cash', '2020-01-02 A "Two"',
    '2020-01-03 ? "Three"', '2020-01-04 open Assets:Bank',
  })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  nav.next_transaction(); assert(vim.fn.line(".") == 3)
  nav.next_transaction(); assert(vim.fn.line(".") == 4)
  nav.next_transaction(); assert(vim.fn.line(".") == 1)
  nav.prev_transaction(); assert(vim.fn.line(".") == 4)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, {
    '; include "ignored.bean"', 'include "books/*.bean"', 'include "spaces here.beancount"',
  })
  local links = nav.find_document_links()
  assert(#links == 2 and links[1].target == "books/*.bean")
end)
vim.fn.delete(root, "rf")
if not ok then print(err); vim.cmd("cquit 1") end
print("Navigation tests passed")
vim.cmd("qa!")
