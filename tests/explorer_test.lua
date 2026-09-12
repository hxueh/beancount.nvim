-- Verify commands and asynchronous results with real Neovim buffers and Python.
vim.opt.runtimepath:prepend(vim.fn.getcwd())
local explorer = require("beancount.explorer")
local config = require("beancount.config")
local directory = vim.fn.tempname()
vim.fn.mkdir(directory, "p")
local file = directory .. "/main.bean"
vim.fn.writefile({
    '2020-01-01 open Assets:Cash USD',
    '2020-01-01 open Equity:Opening USD',
    '2020-01-02 * "Payee" #trip ^receipt',
    '  Assets:Cash 10 USD',
    '  Equity:Opening -10 USD',
    '2020-01-03 query "cash" "SELECT account LIMIT 1"',
}, file)
local ok, err = pcall(function()
    config.setup({ python_path = vim.env.BEANCOUNT_TEST_PYTHON, main_bean_file = file })
    vim.cmd("edit " .. vim.fn.fnameescape(file))
    vim.bo.filetype = "beancount"
    local source = vim.api.nvim_get_current_buf()
    explorer.setup()
    explorer.setup() -- Commands must tolerate repeated plugin initialization.
    explorer.setup_buffer(source)
    assert(vim.fn.maparg("gr", "n") ~= "")
    assert(explorer.token_at('  Assets:Épargne 1 USD', 12) == 'Assets:Épargne')
    assert(explorer.token_at('2020-01-01 * "#trip" ; Assets:Cash', 15) == nil)
    assert(explorer.token_at('  Assets:Cash 1 USD ; ^receipt', 25) == nil)
    assert(explorer.token_at('2020-01-01 * "x" #trip ^receipt', 18) == '#trip')
    local function finish()
        assert(vim.wait(10000, function() return next(explorer.requests) == nil end, 10), "request timeout")
    end
    vim.api.nvim_win_set_cursor(0, { 4, 7 })
    vim.cmd("BeancountReferences")
    finish()
    assert(#vim.fn.getqflist() == 2)
    assert(vim.fn.getqflist()[2].lnum == 4)
    vim.cmd("cclose")
    vim.api.nvim_set_current_buf(source)
    vim.api.nvim_win_set_cursor(0, { 4, 7 })
    vim.cmd("BeancountBalance")
    finish()
    assert(vim.bo.buftype == "nofile")
    local rendered = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
    assert(rendered:find("Before: 0", 1, true) and rendered:find("After:  10 USD", 1, true), rendered)
    assert(not vim.bo.modifiable)
    vim.cmd("close")
    vim.api.nvim_set_current_buf(source)
    vim.api.nvim_win_set_cursor(0, { 6, 0 })
    vim.cmd("BeancountQuery")
    finish()
    rendered = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
    assert(rendered:find("Assets:Cash", 1, true) and rendered:find("1 rows", 1, true), rendered)
    vim.cmd("close")
    vim.api.nvim_set_current_buf(source)
    vim.cmd("BeancountQuery SELECT account WHERE account = 'Missing'")
    finish()
    assert(table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false)):find("0 rows", 1, true))
    vim.cmd("close")
    vim.api.nvim_set_current_buf(source)
    local called = false
    explorer.request({ action = "references", token = "Assets:Cash" }, function() called = true end)
    vim.api.nvim_buf_set_lines(source, 0, 0, false, { ';; changed during request' })
    finish()
    assert(not called, "stale locations must not be displayed")
    -- Range execution reads BQL directly from selected lines, including unsaved text.
    vim.api.nvim_buf_set_lines(source, 0, -1, false, { 'SELECT 1' })
    -- BQL is selected in an unrelated buffer; ledger snapshots must remain valid.
    vim.bo.filetype = "text"
    vim.cmd("1,1BeancountQuery")
    finish()
    assert(vim.bo.buftype == "nofile")
end)
vim.fn.delete(directory, "rf")
if not ok then print(err); vim.cmd("cquit 1") end
print("Explorer integration tests passed")
vim.cmd("qa!")
