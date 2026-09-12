-- Keep validation results attached to their ledger and editor revision. A slow
-- process must never replace a newer result or clear another ledger's errors.
local M = { states = {} }
local utils = require("beancount.utils")
local config = require("beancount.config")
M.namespace = vim.api.nvim_create_namespace("beancount-diagnostics")

local function canonical(path)
  return vim.loop.fs_realpath(path) or vim.fn.fnamemodify(path, ":p")
end

function M.get_state(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) then return nil end
  local root = vim.api.nvim_buf_call(buf, utils.get_main_bean_file)
  if root == "" then return nil end
  root = canonical(root)
  if not M.states[root] then
    M.states[root] = { root = root, generation = 0, pending = 0, buffers = {}, files = {} }
  end
  return M.states[root]
end

-- Include all loaded snapshots: the official loader chooses which files belong
-- to this root, including files outside its directory and symlink aliases.
local function snapshots()
  local texts, ticks = {}, {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == "beancount" then
      local name = vim.api.nvim_buf_get_name(buf)
      if name ~= "" then
        texts[canonical(name)] = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n") .. "\n"
        ticks[buf] = vim.api.nvim_buf_get_changedtick(buf)
      end
    end
  end
  return texts, ticks
end

local function decode(output)
  local ok, data = pcall(vim.json.decode, output or "")
  if not ok or type(data) ~= "table" or data.version ~= 1 or type(data.root) ~= "string" then return nil end
  for _, key in ipairs({ "files", "errors", "flags", "completion", "hints", "postings" }) do
    if type(data[key]) ~= "table" then return nil end
  end
  for _, key in ipairs({ "accounts", "commodities", "payees", "narrations", "tags", "links", "options" }) do
    if type(data.completion[key]) ~= "table" then return nil end
  end
  for name, account in pairs(data.completion.accounts) do
    if type(name) ~= "string" or type(account) ~= "table" or type(account.file) ~= "string"
      or type(account.line) ~= "number" or type(account.balance) ~= "table"
      or type(account.currencies) ~= "table" then return nil end
  end
  if type(data.hints.automatics) ~= "table" then return nil end
  for _, file in ipairs(data.files) do if type(file) ~= "string" then return nil end end
  for _, records in ipairs({ data.errors, data.flags }) do
    for _, record in ipairs(records) do
      if type(record) ~= "table" or type(record.file) ~= "string" or type(record.line) ~= "number"
        or type(record.message) ~= "string" then return nil end
    end
  end
  for file, lines in pairs(data.hints.automatics) do
    if type(file) ~= "string" or type(lines) ~= "table" then return nil end
    for line, amounts in pairs(lines) do
      if not tonumber(line) or type(amounts) ~= "table" then return nil end
      for _, amount in ipairs(amounts) do if type(amount) ~= "string" then return nil end end
    end
  end
  return data
end
M.decode = decode

local function current(ticks, files)
  local included = {}
  for _, file in ipairs(files) do included[canonical(file)] = true end
  for buf, tick in pairs(ticks) do
    if not vim.api.nvim_buf_is_valid(buf) then return false end
    if included[canonical(vim.api.nvim_buf_get_name(buf))]
      and vim.api.nvim_buf_get_changedtick(buf) ~= tick then return false end
  end
  return true
end

function M.show_errors(errors, files)
  local by_file = {}
  for _, file in ipairs(files or {}) do by_file[file] = {} end
  for _, err in ipairs(errors) do
    by_file[err.file] = by_file[err.file] or {}
    table.insert(by_file[err.file], {
      lnum = math.max((err.line or 1) - 1, 0), col = 0,
      message = err.message, severity = vim.diagnostic.severity.ERROR, source = "Beancount",
    })
  end
  for file, records in pairs(by_file) do
    local buf = vim.fn.bufnr(file)
    if buf ~= -1 then vim.diagnostic.set(M.namespace, buf, records) end
  end
end

function M.show_flags(flags)
  for _, flag in ipairs(flags) do
    local severity = config.get("flag_warnings")[flag.flag]
    local buf = vim.fn.bufnr(flag.file)
    if type(severity) == "number" and severity >= 1 and severity <= 4 and buf ~= -1 then
      local records = vim.diagnostic.get(buf, { namespace = M.namespace })
      table.insert(records, { lnum = math.max(flag.line - 1, 0), col = 0, message = flag.message,
        severity = severity, source = "Beancount", user_data = { flag = flag.flag } })
      vim.diagnostic.set(M.namespace, buf, records)
    end
  end
end

function M.process_diagnostics(output, state, ticks)
  local data = decode(output)
  if not data then return false end
  state = state or M.get_state()
  if not state or canonical(data.root) ~= state.root then return false end
  if ticks and not current(ticks, data.files) then return false end
  local files = vim.list_extend(vim.deepcopy(state.files), data.files)
  state.data, state.files, state.ticks = data, data.files, ticks or select(2, snapshots())
  M.show_errors(data.errors, files)
  M.show_flags(data.flags)
  require("beancount.inlay_hints").update_visible_buffers()
  return true
end

local function command(state, hints_only)
  local args = { utils.get_plugin_dir() .. "/pythonFiles/beancheck.py", state.root, "--json", "--stdin" }
  if hints_only then
    table.insert(args, "--hints-only")
  elseif config.get("complete_payee_narration") then
    table.insert(args, "--payeeNarration")
  end
  -- Default OK flags and booked postings can dwarf the useful editor response.
  local selected = {}
  for flag, severity in pairs(config.get("flag_warnings") or {}) do
    if type(severity) == "number" and severity >= 1 and severity <= 4 then table.insert(selected, flag) end
  end
  vim.list_extend(args, { "--flags", table.concat(selected) })
  return utils.get_python_path(), args
end

function M.check_file()
  local buf = vim.api.nvim_get_current_buf()
  local state = M.get_state(buf)
  if not state or not utils.file_exists(state.root) then return end
  state.generation = state.generation + 1
  -- Keep only the newest request while a ledger is loading. Snapshots are taken
  -- when the queued job starts, so intermediate edits never build up a backlog.
  if state.running or state.sync then state.queued = buf; return end
  state.queued = nil
  local generation = state.generation
  local texts, ticks = snapshots()
  local python, args = command(state)
  local running = {}
  state.running = running
  running.id = utils.run_cmd(python, args, function(stdout, stderr, code)
    if state.running == running then state.running = nil end
    if state.generation == generation then
      if code ~= 0 then
        vim.notify("Beancount check failed: " .. stderr, vim.log.levels.ERROR)
      elseif not M.process_diagnostics(stdout, state, ticks) and current(ticks, state.files) then
        vim.notify("Beancount returned an invalid or mismatched response", vim.log.levels.ERROR)
      end
    end
    local queued, pending = state.queued, state.pending
    state.queued = nil
    if queued and not state.sync and vim.api.nvim_buf_is_valid(queued) then
      vim.schedule(function()
        if state.pending == pending and vim.api.nvim_buf_is_valid(queued) and not state.running then
          vim.api.nvim_buf_call(queued, M.check_file)
        end
      end)
    end
  end, { stdin = vim.json.encode(texts), timeout_ms = config.get("validation_timeout_ms") })
end

-- Used for both inference and candidate validation. Neither operation writes
-- ledger files; errors prevent autofill from applying any proposed changes.
function M.check_file_sync(overrides)
  local state = M.get_state()
  if not state or not utils.file_exists(state.root) then return nil end
  local texts, ticks = snapshots()
  for path, text in pairs(overrides or {}) do texts[canonical(path)] = text end
  -- A save supersedes background work. Reap that process before starting the
  -- synchronous validator so the same ledger never has two loaders running.
  state.sync = true
  state.generation, state.pending = state.generation + 1, state.pending + 1
  state.queued = nil
  if state.running and state.running.id and state.running.id > 0 then
    vim.fn.jobstop(state.running.id)
    local status = vim.fn.jobwait({ state.running.id }, 1000)[1]
    if status == -1 then
      state.sync = false
      vim.notify("Beancount could not stop background validation", vim.log.levels.ERROR)
      return nil
    end
    state.running = nil
  end
  local python, args = command(state, true)
  local output, code, stderr = utils.run_cmd_sync(python, args, vim.json.encode(texts),
    config.get("validation_timeout_ms"))
  state.sync = false
  if code ~= 0 then
    vim.notify("Beancount autofill check failed: " .. (stderr or "unknown process error"), vim.log.levels.ERROR)
    return nil
  end
  local data = code == 0 and decode(output) or nil
  if not data or canonical(data.root) ~= state.root then
    vim.notify("Beancount autofill received an invalid or mismatched response", vim.log.levels.ERROR)
    return nil
  end
  -- jobwait processes callbacks; never apply inference if a callback changed
  -- any included buffer while the synchronous validator was running.
  if not current(ticks, data.files) or #data.errors > 0 then return nil end
  return data.hints
end

function M.refresh(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local state = M.get_state(buf)
  if not state then return end
  state.pending = state.pending + 1
  state.generation = state.generation + 1 -- Invalidate results before the debounce expires.
  state.queued = nil -- A newer edit must finish its debounce before being loaded.
  local pending = state.pending
  vim.defer_fn(function()
    if state.pending == pending and vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_call(buf, M.check_file)
    end
  end, config.get("validation_debounce_ms"))
end

function M.get_completion_data()
  local state = M.get_state()
  return state and state.data and vim.json.encode(state.data.completion) or nil
end

function M.get_hints_data(buf)
  local state = M.get_state(buf)
  if state and state.data and current(state.ticks, state.files) then
    return vim.json.encode(state.data.hints)
  end
end

function M.setup()
  local group = vim.api.nvim_create_augroup("BeancountValidation", { clear = true })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = group, pattern = { "*.bean", "*.beancount", "*.bean.oneline", "*.beancount.oneline" },
    callback = function(args) M.refresh(args.buf) end,
  })
end
return M
