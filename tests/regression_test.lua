-- Exercise real Neovim APIs and the Python output contract; mocks in individual
-- module tests cannot catch schema mismatches or LuaJIT dependency errors.
vim.opt.runtimepath:prepend(vim.fn.getcwd())
local config = require("beancount.config")
local autofill = require("beancount.autofill")
local hints = require("beancount.inlay_hints")
local diagnostics = require("beancount.diagnostics")
local failures = 0
local function check(name, fn)
  config.setup({ auto_format_on_save = false })
  local ok, err = pcall(fn)
  print((ok and "PASS " or "FAIL ") .. name .. (ok and "" or ": " .. tostring(err)))
  if not ok then
    failures = failures + 1
  end
end

check("nested configuration reads and writes real nested fields", function()
  config.setup({ snippets = { date_format = "%d/%m/%Y" } })
  assert(config.get("snippets.date_format") == "%d/%m/%Y")
  config.set("ui.virtual_text", false)
  assert(config.get_all().ui.virtual_text == false)
  assert(config.get_all()["ui.virtual_text"] == nil)
end)

check("CJK width works without an external utf8 module", function()
  config.set("fixed_cjk_width", true)
  local formatter = require("beancount.formatter")
  assert(formatter.display_width("A中文あ한😀") == 10)
end)

local filename = vim.fn.tempname() .. ".bean"
vim.fn.writefile({
  '2025-01-01 open Assets:Cash USD',
  '2025-01-01 open Equity:Opening USD',
  '2025-01-02 * "Opening"',
  '  Assets:Cash  100 USD',
  '  Equity:Opening',
}, filename)
vim.cmd("edit " .. vim.fn.fnameescape(filename))
vim.bo.filetype = "beancount"
local buf = vim.api.nvim_get_current_buf()
filename = vim.api.nvim_buf_get_name(buf)
local python = vim.env.BEANCOUNT_TEST_PYTHON or ".venv/bin/python"

check("backend output renders hints and clears removed postings", function()
  local output = vim.fn.system({ python, "pythonFiles/beancheck.py", filename, "--json" })
  assert(vim.v.shell_error == 0, output)
  assert(diagnostics.process_diagnostics(output))
  assert(#vim.api.nvim_buf_get_extmarks(buf, hints.namespace, 0, -1, {}) == 1)
  local data = vim.json.decode(output)
  data.hints.automatics = {}
  assert(diagnostics.process_diagnostics(vim.json.encode(data)))
  assert(#vim.api.nvim_buf_get_extmarks(buf, hints.namespace, 0, -1, {}) == 0)
end)

check("disabling hints removes existing marks", function()
  diagnostics.states = {}
  hints.update_data(vim.json.encode({ [filename] = { ["5"] = { "-100 USD" } } }))
  assert(#vim.api.nvim_buf_get_extmarks(buf, hints.namespace, 0, -1, {}) == 1)
  config.set("inlay_hints", false)
  hints.render_hints(buf)
  assert(#vim.api.nvim_buf_get_extmarks(buf, hints.namespace, 0, -1, {}) == 0)
end)

check("failed validation cannot apply cached amounts", function()
  config.set("auto_fill_amounts", true)
  config.set("main_bean_file", filename .. ".missing")
  autofill.update_data(vim.json.encode({ [filename] = { ["5"] = { "999 USD" } } }))
  assert(autofill.fill_buffer(buf) == false)
  assert(vim.api.nvim_buf_get_lines(buf, 4, 5, false)[1] == "  Equity:Opening")
  assert(vim.tbl_isempty(autofill.automatics))
end)

check("cost enhancement preserves prices, labels, quantities, and comments", function()
  local original = {
    '  Assets:Stock  -1 ABC {10 USD, "lot; @ } label"} @ 15 USD ; retain this',
    '  Assets:Stock  -2 ABC {10 USD} @@ 30 USD ; total proceeds',
    '  Assets:Stock  1 ABC {10 USD, 2024-01-01, "lot"} ; keep',
    '  Assets:Stock  1 ABC {{10 USD}} ; total cost specification',
    '  Assets:Stock  -1 ABC {} ; infer lot',
  }
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, original)
  autofill.cost_basis_data = { [filename] = {} }
  for i = 1, #original do
    autofill.cost_basis_data[filename][tostring(i)] = '999 ABC {10 USD, 2025-01-01} @@ 10.00 USD'
  end
  assert(not autofill.enhance_cost_basis(buf))
  assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), original),
    "costs, labels, quantities, prices and comments must remain exactly as authored")
end)

check("posting expansion preserves subsequent authored costs", function()
  config.set("auto_fill_amounts", true)
  config.set("python_path", python)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    '2025-01-01 open Assets:Cash',
    '2025-01-01 open Equity:Opening',
    '2025-01-01 open Assets:Stock ABC',
    '2025-01-02 * "Mixed currencies"',
    '  Equity:Opening -1 USD',
    '  Equity:Opening -2 EUR',
    '  ! Assets:Cash ; keep flag and comment',
    '2025-01-03 * "Buy"',
    '  Assets:Stock  1 ABC {10 USD, 2025-01-03, "lot"} @ 10 USD ; keep',
    '  Assets:Cash -10 USD',
  })
  assert(autofill.fill_buffer(buf))
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  assert(#lines == 11)
  assert(lines[7]:match('^  ! Assets:Cash') and lines[7]:find('; keep flag and comment', 1, true))
  assert(lines[8]:match('^  ! Assets:Cash'))
  assert(lines[10] == '  Assets:Stock  1 ABC {10 USD, 2025-01-03, "lot"} @ 10 USD ; keep', lines[10])
  assert(not autofill.fill_buffer(buf), "autofill must be idempotent")
end)

vim.api.nvim_buf_delete(buf, { force = true })
vim.fn.delete(filename)
if failures > 0 then
  vim.cmd("cquit 1")
else
  vim.cmd("qa!")
end
