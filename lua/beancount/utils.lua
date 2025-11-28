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

  local job_id = vim.fn.jobstart(vim.list_extend({ cmd }, args), {
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
      local stdout_str = table.concat(stdout, "\n")
      local stderr_str = table.concat(stderr, "\n")

      if callback then
        callback(stdout_str, stderr_str, exit_code)
      end
    end,
  })

  return job_id
end

-- Execute a command synchronously and return the result
-- @param cmd string: Command to execute
-- @param args table: Command arguments
-- @return string, number: stdout output and exit code
M.run_cmd_sync = function(cmd, args)
  local full_cmd = vim.list_extend({ cmd }, args)
  local result = vim.fn.system(full_cmd)
  local exit_code = vim.v.shell_error
  return result, exit_code
end

-- Resolve the path to the main beancount file
-- Falls back to current file if no main file is configured
-- @return string: Absolute path to main beancount file or empty string
M.get_main_bean_file = function()
  local config = require("beancount.config")
  local main_file = config.get("main_bean_file")

  if not main_file or main_file == "" then
    -- Default to current file if it's a beancount file and no main file specified
    local current_file = vim.fn.expand("%:p")
    if vim.bo.filetype == "beancount" then
      return current_file
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
