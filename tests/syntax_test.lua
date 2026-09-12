-- Keep editor token recognition tied to fixtures accepted by the Python loader.
vim.opt.runtimepath:prepend(vim.fn.getcwd())
local syntax = require("beancount.syntax")
local completion = require("beancount.completion")
local formatter = require("beancount.formatter")
require("beancount.config").setup({})
local fixtures = vim.json.decode(table.concat(vim.fn.readfile("tests/example/editor_syntax.json"), "\n"))
local ok, err = pcall(function()
  for _, marker in ipairs(fixtures.transaction_markers) do
    local line = '2020/01/02 ' .. marker .. ' "Payee'
    assert(completion.is_payee_context(line, #line + 1), line)
    line = line .. '\\" escaped" "Narration'
    assert(completion.is_narration_context(line, #line + 1), line)
    assert(not completion.is_payee_context(line, #line + 1), line)
    line = line .. '" ; "comment'
    assert(not completion.is_narration_context(line, #line + 1), line)
  end
  for _, flag in ipairs(fixtures.posting_flags) do
    local line = '  ' .. flag .. ' Assets:Cash 10.00 USD ; keep'
    assert(syntax.posting(line), line)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { line })
    formatter.format_buffer()
    assert(vim.api.nvim_get_current_line():match('^  ' .. vim.pesc(flag) .. ' Assets:Cash%s+10.00 USD ; keep$'))
    local prefix = '  ' .. flag .. ' As'
    assert(completion.is_account_context(prefix, #prefix + 1))
  end
  for _, expression in ipairs(fixtures.expressions) do
    for _, prefix in ipairs({ '  Assets:Cash ', '  ! Assets:Cash ' }) do
      for _, currency in ipairs({ '', 'U', 'USD' }) do
        local line = prefix .. expression .. ' ' .. currency
        assert(completion.is_commodity_context(line, #line + 1), line)
        assert(completion.get_account_on_line(line) == 'Assets:Cash', line)
      end
    end
  end
  for _, line in ipairs({ '  Assets:Cash (100 + ) ', '  Assets:Cash 100 + ',
    '  Assets:Cash 100 ; note ', '  Assets:Cash "100" ', '  description: 100 ',
    '2020-01-02 * "Assets:Cash 100 ' }) do
    assert(not completion.is_commodity_context(line, #line + 1), line)
  end
end)
if not ok then print(err); vim.cmd('cquit 1') end
print('Editor syntax fixtures passed')
vim.cmd('qa!')
