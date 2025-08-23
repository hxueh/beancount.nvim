-- Beancount diagnostics module
-- Handles error checking and validation using the external beancheck.py script
-- Displays errors, warnings, and flag-based diagnostics in Neovim
local M = {}

local utils = require("beancount.utils")
local config = require("beancount.config")

-- Create diagnostic namespace for Neovim's diagnostic system
local namespace = vim.api.nvim_create_namespace("beancount-diagnostics")

-- Initialize the diagnostics module
-- Currently no global setup required
M.setup = function()
	-- No global initialization needed
end

-- Run beancount validation on the main beancount file
-- Executes the external Python script to validate syntax and generate completions
M.check_file = function()
	local main_file = utils.get_main_bean_file()
	if main_file == "" or not utils.file_exists(main_file) then
		return
	end

	local plugin_dir = utils.get_plugin_dir()
	local check_script = plugin_dir .. "/pythonFiles/beancheck.py"
	local python_path = config.get("python_path")

	-- Handle environment variable expansion in python_path (e.g., %PYTHON_HOME%)
	if python_path:match("^%%") then
		python_path = utils.resolve_env_vars(python_path)
	end

	-- Expand ~ to user home directory in python_path
	if python_path:sub(1, 1) == "~" then
		python_path = os.getenv("HOME") .. python_path:sub(2)
	end

	local args = { check_script, main_file }
	if config.get("complete_payee_narration") then
		table.insert(args, "--payeeNarration")
	end

	utils.run_cmd(python_path, args, function(stdout, stderr, exit_code)
		if exit_code == 0 and stdout then
			M.process_diagnostics(stdout)
		else
			vim.notify("Beancount check failed: " .. (stderr or "Unknown error"), vim.log.levels.ERROR)
		end
	end)
end

-- Process the multi-line JSON output from beancheck.py
-- @param output string: Multi-line output containing errors, completions, flags, and hints
M.process_diagnostics = function(output)
	local lines = vim.split(output, "\n", { plain = true })
	if #lines < 4 then
		return
	end

	local errors_json = lines[1]
	local completions_json = lines[2]
	local flags_json = lines[3]
	local hints_json = lines[4]

	-- Parse and display validation errors
	local ok, errors = pcall(vim.json.decode, errors_json)
	if ok and errors then
		M.show_errors(errors)
	end

	-- Parse and display flag-based warnings
	local flags_ok, flags = pcall(vim.json.decode, flags_json)
	if flags_ok and flags then
		M.show_flags(flags)
	end

	-- Update completion module with latest data from beancount files
	M.completion_data = completions_json
	local completion = require("beancount.completion")
	completion.update_data(completions_json)

	-- Update inlay hints module with automatic posting data
	M.hints_data = hints_json
	local inlay_hints = require("beancount.inlay_hints")
	inlay_hints.update_data(hints_json)
end

-- Display validation errors in Neovim's diagnostic system
-- @param errors table: Array of error objects with file, line, message
M.show_errors = function(errors)
	local diagnostics_by_file = {}

	for _, error in ipairs(errors) do
		local file = error.file
		local line = (error.line or 1) - 1 -- Convert to 0-based indexing, default to line 1
		local message = error.message or "Unknown error"

		if not diagnostics_by_file[file] then
			diagnostics_by_file[file] = {}
		end

		table.insert(diagnostics_by_file[file], {
			lnum = math.max(line, 0),
			end_lnum = math.max(line, 0),
			col = 0,
			end_col = -1,
			message = message,
			severity = vim.diagnostic.severity.ERROR,
			source = "Beancount",
		})
	end

	-- Clear any existing diagnostics before setting new ones
	vim.diagnostic.reset(namespace)

	-- Apply diagnostics to each file that has errors
	for file, file_diagnostics in pairs(diagnostics_by_file) do
		if utils.file_exists(file) then
			local bufnr = vim.fn.bufnr(file)
			if bufnr ~= -1 then
				vim.diagnostic.set(namespace, bufnr, file_diagnostics)
			end
		end
	end
end

-- Display flag-based warnings in Neovim's diagnostic system
-- @param flags table: Array of flag objects with file, line, flag, message
M.show_flags = function(flags)
	local flag_warnings = config.get("flag_warnings")
	local diagnostics_by_file = {}

	for _, flag in ipairs(flags) do
		local warning_type = flag_warnings[flag.flag]
		if warning_type then
			local file = flag.file
			local line = flag.line - 1 -- Convert to 0-based indexing
			local message = flag.message

			if not diagnostics_by_file[file] then
				diagnostics_by_file[file] = {}
			end

			local severity = vim.diagnostic.severity.WARN
			if warning_type == 1 then
				severity = vim.diagnostic.severity.WARN
			elseif warning_type == 2 then
				severity = vim.diagnostic.severity.INFO
			elseif warning_type == 3 then
				severity = vim.diagnostic.severity.HINT
			end

			table.insert(diagnostics_by_file[file], {
				lnum = math.max(line, 0),
				end_lnum = math.max(line, 0),
				col = 0,
				end_col = -1,
				message = message,
				severity = severity,
				source = "Beancount",
				user_data = {
					flag = flag.flag,
				},
			})
		end
	end

	-- Merge flag warnings with existing error diagnostics
	for file, file_diagnostics in pairs(diagnostics_by_file) do
		if utils.file_exists(file) then
			local bufnr = vim.fn.bufnr(file)
			if bufnr ~= -1 then
				local existing = vim.diagnostic.get(bufnr, { namespace = namespace })
				vim.list_extend(existing, file_diagnostics)
				vim.diagnostic.set(namespace, bufnr, existing)
			end
		end
	end
end

-- Refresh diagnostics with a small delay
-- Called after file saves to re-validate the beancount files
M.refresh = function()
	vim.defer_fn(function()
		M.check_file()
	end, 100) -- Delay ensures file write operations complete before validation
end

-- Get the cached completion data
-- @return string: JSON string with completion data
M.get_completion_data = function()
	return M.completion_data
end

-- Get the cached inlay hints data
-- @return string: JSON string with automatic posting data
M.get_hints_data = function()
	return M.hints_data
end

return M
