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

	-- Convert relative paths to absolute paths
	if main_file and not vim.startswith(main_file, "/") then
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
	return filename:match("%.([^.]+)$")
end

-- Check if a file exists on the filesystem
-- @param path string: Path to check
-- @return boolean: True if file exists
M.file_exists = function(path)
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
