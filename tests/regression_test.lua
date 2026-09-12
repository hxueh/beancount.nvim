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
  local output = vim.fn.system({ python, "pythonFiles/beancheck.py", filename })
  assert(vim.v.shell_error == 0, output)
  diagnostics.process_diagnostics(output)
  assert(#vim.api.nvim_buf_get_extmarks(buf, hints.namespace, 0, -1, {}) == 1)
  hints.update_data('{"automatics":{},"cost_basis":{}}')
  assert(#vim.api.nvim_buf_get_extmarks(buf, hints.namespace, 0, -1, {}) == 0)
end)

check("disabling hints removes existing marks", function()
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
  assert(autofill.enhance_cost_basis(buf))
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  assert(lines[1] == '  Assets:Stock  -1 ABC {10 USD, "lot; @ } label", 2025-01-01} @ 15 USD ; retain this', lines[1])
  assert(lines[2] == '  Assets:Stock  -2 ABC {10 USD, 2025-01-01} @@ 30 USD ; total proceeds', lines[2])
  assert(lines[3] == '  Assets:Stock  1 ABC {10 USD, 2024-01-01, "lot"} @@ 10.00 USD ; keep', lines[3])
  assert(lines[4] == original[4])
  assert(lines[5] == original[5])
  assert(not autofill.enhance_cost_basis(buf), "enhancement must be idempotent")
end)

check("cost annotations use original line numbers before posting expansion", function()
  config.set("auto_fill_amounts", true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    '  Assets:Cash', '  Assets:Stock  1 ABC {10 USD}',
  })
  local original_check = diagnostics.check_file_sync
  diagnostics.check_file_sync = function()
    return {
      automatics = { [filename] = { ["1"] = { "1 USD", "2 EUR" } } },
      cost_basis = { [filename] = { ["2"] = '1 ABC {10 USD, 2025-01-01} @@ 10.00 USD' } },
    }
  end
  local ok, result = pcall(autofill.fill_buffer, buf)
  diagnostics.check_file_sync = original_check
  assert(ok and result, tostring(result))
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  assert(#lines == 3)
  assert(lines[3] == '  Assets:Stock  1 ABC {10 USD, 2025-01-01} @@ 10.00 USD', lines[3])
end)

vim.api.nvim_buf_delete(buf, { force = true })
vim.fn.delete(filename)
if failures > 0 then
  vim.cmd("cquit 1")
else
  vim.cmd("qa!")
end
