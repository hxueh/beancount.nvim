-- Exercise real process pipes and editor revisions, then control completion
-- order to prove that slow jobs cannot overlap or publish stale results.
vim.opt.runtimepath:prepend(vim.fn.getcwd())
local config = require('beancount.config')
local utils = require('beancount.utils')
local diagnostics = require('beancount.diagnostics')
local python = vim.env.BEANCOUNT_TEST_PYTHON or '.venv/bin/python'
local directory = vim.fn.tempname()
vim.fn.mkdir(directory, 'p')
directory = vim.loop.fs_realpath(directory)
local filename = directory .. '/main.bean'
vim.fn.writefile({
  'option "insert_pythonpath" "TRUE"', 'plugin "chatty"',
  '2020-01-01 open Assets:Cash USD', '2020-01-01 open Equity:Opening USD',
  '2020-01-02 * "Entry"', '  Assets:Cash 1 USD', '  ! Equity:Opening',
}, filename)
vim.fn.writefile({ '__plugins__ = ("run",)', 'def run(entries, options):',
  '    print("plugin progress")', '    return entries, []' }, directory .. '/chatty.py')
vim.cmd('edit ' .. vim.fn.fnameescape(filename))
vim.bo.filetype = 'beancount'
local buf = vim.api.nvim_get_current_buf()
local failures = 0
local function check(name, fn)
  config.setup({ python_path = python, main_bean_file = filename, auto_format_on_save = false,
    validation_debounce_ms = 10, validation_timeout_ms = 2000 })
  local ok, err = pcall(fn)
  print((ok and 'PASS ' or 'FAIL ') .. name .. (ok and '' or ': ' .. tostring(err)))
  if not ok then failures = failures + 1 end
end
check('sync pipes preserve JSON from a chatty plugin', function()
  local hints = diagnostics.check_file_sync()
  assert(hints and hints.automatics[filename]['7'][1] == '-1 USD')
  config.set('auto_fill_amounts', true)
  assert(require('beancount.autofill').fill_buffer(buf))
  assert(vim.api.nvim_buf_get_lines(buf, 6, 7, false)[1] == '  ! Equity:Opening  -1 USD')
end)
check('sync process failures and timeouts are bounded', function()
  local out, code, stderr = utils.run_cmd_sync(python,
    { '-c', 'import sys; print("out"); print("err", file=sys.stderr); sys.exit(7)' }, nil, 2000)
  assert(code == 7 and out:find('out') and not out:find('err') and stderr:find('err'))
  local start = vim.loop.hrtime()
  out, code, stderr = utils.run_cmd_sync(python, { '-c', 'import time; time.sleep(10)' }, nil, 50)
  assert(code == 124 and stderr:find('timed out'), tostring(code) .. ': ' .. stderr)
  assert((vim.loop.hrtime() - start) / 1e9 < 2)
end)
check('async timeout releases the process', function()
  local result
  utils.run_cmd(python, { '-c', 'import time; time.sleep(10)' }, function(_, stderr, code)
    result = { code, stderr }
  end, { timeout_ms = 50 })
  assert(vim.wait(2000, function() return result ~= nil end))
  assert(result[1] == 124 and result[2]:find('timed out'))
end)
check('autofill reports a timeout without changing the buffer', function()
  vim.api.nvim_buf_set_lines(buf, 6, 7, false, { '  ! Equity:Opening' })
  vim.fn.writefile({ '__plugins__ = ("run",)', 'def run(entries, options):',
    '    import time; time.sleep(10)', '    return entries, []' }, directory .. '/chatty.py')
  config.set('validation_timeout_ms', 50)
  config.set('auto_fill_amounts', true)
  local before = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local original_notify, message = vim.notify, nil
  vim.notify = function(text) message = text end
  local ok, result = pcall(require('beancount.autofill').fill_buffer, buf)
  vim.notify = original_notify
  assert(ok and not result)
  assert(message and message:find('timed out'))
  assert(vim.deep_equal(before, vim.api.nvim_buf_get_lines(buf, 0, -1, false)))
end)
check('completed postings skip save-time validation', function()
  vim.api.nvim_buf_set_lines(buf, 6, 7, false, { '  ! Equity:Opening -1 USD' })
  config.set('auto_fill_amounts', true)
  local original = diagnostics.check_file_sync
  diagnostics.check_file_sync = function() error('unnecessary load') end
  local ok, result = pcall(require('beancount.autofill').fill_buffer, buf)
  diagnostics.check_file_sync = original
  assert(ok and not result)
end)
check('save reaps background validation before starting another loader', function()
  -- A second process reports an error if the first process is still alive.
  -- The mode file lets the first process be slow and the save-time check fast.
  vim.fn.writefile({
    '__plugins__ = ("run",)', 'def run(entries, options):',
    '    import os, pathlib, time',
    '    root = pathlib.Path(__file__).parent',
    '    marker = root / "running-pid"',
    '    if marker.exists():',
    '        try: os.kill(int(marker.read_text()), 0)',
    '        except ProcessLookupError: pass',
    '        else: raise RuntimeError("overlapping loaders")',
    '    marker.write_text(str(os.getpid()))',
    '    if not (root / "fast").exists(): time.sleep(10)',
    '    return entries, []',
  }, directory .. '/chatty.py')
  diagnostics.states = {}
  diagnostics.check_file()
  assert(vim.wait(1000, function() return vim.fn.filereadable(directory .. '/running-pid') == 1 end))
  vim.fn.writefile({}, directory .. '/fast')
  local hints = diagnostics.check_file_sync()
  assert(hints, 'save failed or two loaders overlapped')
  assert(not diagnostics.get_state().running)
end)
check('one running job and one latest request per ledger', function()
  diagnostics.states = {}
  local original_run, original_process = utils.run_cmd, diagnostics.process_diagnostics
  local jobs, published, active, maximum = {}, {}, 0, 0
  utils.run_cmd = function(_, _, callback, opts)
    active = active + 1
    maximum = math.max(maximum, active)
    table.insert(jobs, { callback = callback, snapshot = vim.json.decode(opts.stdin)[filename] })
    return #jobs
  end
  diagnostics.process_diagnostics = function(output) table.insert(published, output); return true end
  local function finish(index)
    active = active - 1
    jobs[index].callback(tostring(index), '', 0)
  end
  local ok, err = pcall(function()
    diagnostics.check_file()
    for i = 1, 10 do
      vim.api.nvim_buf_set_lines(buf, -1, -1, false, { '; edit ' .. i })
      diagnostics.refresh(buf)
    end
    vim.wait(40, function() return false end)
    assert(#jobs == 1)
    finish(1)
    assert(vim.wait(500, function() return #jobs == 2 end))
    assert(jobs[2].snapshot:find('; edit 10', 1, true))
    finish(2)
    assert(maximum == 1 and #jobs == 2)
    assert(vim.deep_equal(published, { '2' }), 'stale result must not publish')
    -- Scheduling is scoped to roots, so another ledger can load independently.
    diagnostics.check_file()
    local other = directory .. '/other.bean'
    vim.fn.writefile({}, other)
    config.set('main_bean_file', other)
    diagnostics.check_file()
    assert(active == 2)
    finish(3); finish(4)
  end)
  utils.run_cmd, diagnostics.process_diagnostics = original_run, original_process
  assert(ok, err)
end)
vim.api.nvim_buf_delete(buf, { force = true })
vim.fn.delete(directory, 'rf')
if failures > 0 then vim.cmd('cquit 1') else vim.cmd('qa!') end
