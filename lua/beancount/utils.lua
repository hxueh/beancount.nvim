-- Utility functions for the beancount extension
-- Provides common helper functions used across the plugin
local M = {}

-- Execute a command asynchronously and handle the results
-- @param cmd string: Command to execute
-- @param args table: Command arguments
-- @param callback function: Called with (stdout, stderr, exit_code)
-- @param opts table: Optional settings (cwd, etc.)
-- @return number: Job ID
M.run_cmd = function(cmd, args, callback, opts)
  opts = opts or {}
  local stdout = {}
  local stderr = {}
  local done, timed_out = false, false

  local started, job_id = pcall(vim.fn.jobstart, vim.list_extend({ cmd }, args), {
    cwd = opts.cwd,
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if data then
        vim.list_extend(stdout, data)
      end
    end,
    on_stderr = function(_, data)
      if data then
        vim.list_extend(stderr, data)
      end
    end,
    on_exit = function(_, exit_code)
      done = true
      if timed_out then exit_code = 124 end
      local stdout_str = table.concat(stdout, "\n")
      local stderr_str = timed_out and "Validation timed out" or table.concat(stderr, "\n")

      if callback then
        callback(stdout_str, stderr_str, exit_code)
      end
    end,
  })

  if not started then
    if callback then callback("", tostring(job_id), -1) end
    return -1
  end
  -- Stop slow validators even when the editor keeps changing. The completion
  -- callback still runs on exit so ledger scheduling can release its slot.
  if job_id > 0 and opts.timeout_ms then
    vim.defer_fn(function()
      if not done then
        timed_out = true
        vim.fn.jobstop(job_id)
      end
    end, opts.timeout_ms)
  end
  if job_id > 0 and opts.stdin then
    vim.fn.chansend(job_id, opts.stdin)
    vim.fn.chanclose(job_id, "stdin")
  elseif job_id <= 0 and callback then
    callback("", "Could not start " .. cmd, -1)
  end
  return job_id
end

-- Execute a command synchronously and return the result
-- @param cmd string: Command to execute
-- @param args table: Command arguments
-- @return string, number, string: stdout, exit code, and stderr
M.run_cmd_sync = function(cmd, args, input, timeout_ms)
  timeout_ms = timeout_ms or 10000
  local output, code, error_output = "", -1, "Could not start " .. cmd
  -- Use the same separate pipes as async validation: plugin progress on stderr
  -- must never become part of the JSON response. jobwait bounds save latency.
  local job = M.run_cmd(cmd, args, function(stdout, stderr, status)
    output, code, error_output = stdout, status, stderr
  end, { stdin = input })
  if job > 0 then
    local status = vim.fn.jobwait({ job }, timeout_ms)[1]
    if status == -1 or status == -2 then
      vim.fn.jobstop(job)
      vim.fn.jobwait({ job }, 1000)
      return "", status == -1 and 124 or 130, status == -1 and "Validation timed out" or "Validation interrupted"
    end
  end
  return output, code, error_output
end

-- Search from the buffer directory, stopping at the nearest repository boundary.
-- Resolving on each use keeps separate ledgers independent of Neovim's cwd.
local function find_upward(names, start_dir)
  local dir = start_dir
  while dir and dir ~= "" do
    for _, name in ipairs(names) do
      local path = dir .. "/" .. name
      if M.file_exists(path) then
        return path
      end
    end
    if vim.loop.fs_stat(dir .. "/.git") then
      break
    end
    local parent = vim.fn.fnamemodify(dir, ":h")
    if parent == dir then
      break
    end
    dir = parent
  end
end

-- Resolve the path to the main beancount file
-- Finds the nearest main.bean/main.beancount, then falls back to the current file
-- @return string: Absolute path to main beancount file or empty string
M.get_main_bean_file = function()
  local config = require("beancount.config")
  local main_file = config.get("main_bean_file")

  if not main_file or main_file == "" then
    -- Only infer a ledger for Beancount buffers; other filetypes have no default.
    local current_file = vim.fn.expand("%:p")
    if vim.bo.filetype == "beancount" then
      return find_upward({ "main.bean", "main.beancount" }, vim.fn.fnamemodify(current_file, ":h")) or current_file
    else
      return ""
    end
  end

  -- Convert main_file to string if it's not already
  main_file = tostring(main_file)

  -- Convert relative paths to absolute paths
  -- Check for Unix absolute paths (/) and Windows absolute paths (C:)
  if main_file and not vim.startswith(main_file, "/") and not main_file:match("^%a:") then
    local cwd = vim.fn.getcwd()
    return cwd .. "/" .. main_file
  end

  return main_file
end

-- Explicit interpreters keep their existing cwd-relative behavior. Otherwise use
-- the ledger's environment so opening an included file from another cwd works.
M.get_python_path = function()
  local path = require("beancount.config").get("python_path")
  if path and path ~= "" then
    path = M.resolve_env_vars(path)
    if path:sub(1, 1) == "~" then
      path = vim.fn.expand("~") .. path:sub(2)
    end
    return path
  end

  local main_file = M.get_main_bean_file()
  local dir = main_file ~= "" and vim.fn.fnamemodify(main_file, ":h") or vim.fn.getcwd()
  local local_python = find_upward({ ".venv/bin/python", ".venv/Scripts/python.exe" }, dir)
  if local_python and vim.fn.executable(local_python) == 1 then
    return local_python
  end
  local env = vim.env.VIRTUAL_ENV
  if env and env ~= "" then
    for _, suffix in ipairs({ "/bin/python", "/Scripts/python.exe" }) do
      if vim.fn.executable(env .. suffix) == 1 then
        return env .. suffix
      end
    end
  end
  return vim.fn.executable("python3") == 1 and "python3" or "python"
end

-- Expand environment variables in path strings
-- Handles Windows-style %VAR% environment variable syntax
-- @param path string: Path with environment variables
-- @return string: Path with variables expanded
M.resolve_env_vars = function(path)
  return path:gsub("%%([^%%]+)%%", function(var)
    return os.getenv(var) or ""
  end)
end

-- Count how many times a character appears in a string
-- @param str string: String to search in
-- @param char string: Character to count
-- @return number: Number of occurrences
M.count_occurrences = function(str, char)
  if not str or not char or str == "" or char == "" then
    return 0
  end
  local count = 0
  for i = 1, #str do
    if str:sub(i, i) == char then
      count = count + 1
    end
  end
  return count
end

-- Check if a value exists in an array-like table
-- @param tbl table: Table to search in
-- @param value any: Value to search for
-- @return boolean: True if value is found
M.tbl_contains = function(tbl, value)
  if not tbl then
    return false
  end
  for _, v in ipairs(tbl) do
    if v == value then
      return true
    end
  end
  return false
end

-- Extract file extension from filename
-- @param filename string: Filename to extract extension from
-- @return string: File extension without dot
M.get_file_extension = function(filename)
  if not filename then
    return nil
  end
  -- Extract just the filename part (after last slash) then get extension
  local basename = filename:match("[^/\\\\]*$")
  if not basename or basename == "" then
    return nil
  end
  return basename:match("%.([^.]+)$")
end

-- Check if a file exists on the filesystem
-- @param path string: Path to check
-- @return boolean: True if file exists
M.file_exists = function(path)
  if not path or path == "" then
    return false
  end
  local stat = vim.loop.fs_stat(path)
  return stat and stat.type == "file"
end

-- Get the root directory of the beancount plugin
-- Uses debug info to determine the plugin's installation path
-- @return string: Absolute path to plugin directory
M.get_plugin_dir = function()
  local info = debug.getinfo(1, "S")
  local script_path = info.source:sub(2) -- Remove '@' prefix
  return vim.fn.fnamemodify(script_path, ":h:h:h") -- Go up 3 levels from lua/beancount/utils.lua
end

return M
