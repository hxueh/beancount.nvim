-- Configuration management module for beancount extension
-- Handles user configuration, validation, and legacy compatibility
local M = {}

-- Default configuration values for all beancount features
-- These can be overridden by user configuration in setup()
local defaults = {
	-- Settings for automatic text alignment in beancount files
	separator_column = 70,
	instant_alignment = true,
	fixed_cjk_width = false,

	-- Configuration for auto-completion features
	complete_payee_narration = true,

	-- Main beancount file path settings
	main_bean_file = "",

	-- Python interpreter configuration for beancount tools
	python_path = "python",

	-- Configuration for diagnostic warnings based on transaction flags
	flag_warnings = {
		["*"] = nil,
		["!"] = vim.diagnostic.severity.WARN,
		["P"] = nil,
		["S"] = nil,
		["T"] = nil,
		["C"] = nil,
		["U"] = nil,
		["R"] = nil,
		["M"] = nil,
	},

	-- Feature toggles for various beancount capabilities
	inlay_hints = true,
	auto_save_before_check = true,
	auto_format_on_save = true,

	-- Configuration for code snippets and templates
	snippets = {
		enabled = true,
		date_format = "%Y-%m-%d", -- ISO format
	},

	-- Default keyboard shortcuts for beancount navigation
	keymaps = {
		goto_definition = "gd",
		next_transaction = "]]",
		prev_transaction = "[[",
	},

	-- User interface configuration for diagnostics display
	ui = {
		virtual_text = true,
		signs = true,
		update_in_insert = false,
		severity_sort = true,
	},
}

M.options = {}

-- Schema for validating configuration values
-- Ensures type safety and range checking for user options
local validation_schema = {
	separator_column = { type = "number", min = 1, max = 200 },
	instant_alignment = { type = "boolean" },
	fixed_cjk_width = { type = "boolean" },
	complete_payee_narration = { type = "boolean" },
	main_bean_file = { type = "string" },
	python_path = { type = "string" },
	flag_warnings = { type = "table" },
	inlay_hints = { type = "boolean" },
	auto_save_before_check = { type = "boolean" },
	auto_format_on_save = { type = "boolean" },
}

-- Validates a single configuration key-value pair
-- @param key string: Configuration key to validate
-- @param value any: Value to validate
-- @return boolean, string?: Success status and error message if validation fails
local function validate_config(key, value)
	local schema = validation_schema[key]
	if not schema then
		return true -- Allow unknown keys for extensibility
	end

	if type(value) ~= schema.type then
		return false, string.format("Expected %s for %s, got %s", schema.type, key, type(value))
	end

	if schema.type == "number" then
		if schema.min and value < schema.min then
			return false, string.format("%s must be >= %d, got %d", key, schema.min, value)
		end
		if schema.max and value > schema.max then
			return false, string.format("%s must be <= %d, got %d", key, schema.max, value)
		end
	end

	return true
end

-- Initialize configuration with user options
-- @param opts table: User configuration options to merge with defaults
M.setup = function(opts)
	opts = opts or {}

	-- Validate all provided configuration options
	for key, value in pairs(opts) do
		local ok, err = validate_config(key, value)
		if not ok then
			vim.notify("Beancount config validation error: " .. err, vim.log.levels.WARN)
		end
	end

	-- Deep merge user options with default configuration
	M.options = vim.tbl_deep_extend("force", {}, defaults, opts)

	-- Support legacy vim global variables for existing users
	M.load_legacy_config()

	-- Configure Neovim's built-in diagnostics with our UI settings
	if M.options.ui then
		---@diagnostic disable-next-line: redundant-parameter
		vim.diagnostic.config({
			virtual_text = M.options.ui.virtual_text,
			signs = M.options.ui.signs,
			update_in_insert = M.options.ui.update_in_insert,
			severity_sort = M.options.ui.severity_sort,
		})
	end
end

-- Load legacy vim global variables for backwards compatibility
-- Maps old vim global variables to new configuration keys
M.load_legacy_config = function()
	local legacy_mappings = {
		beancount_separator_column = "separator_column",
		beancount_instant_alignment = "instant_alignment",
		beancount_main_bean_file = "main_bean_file",
		beancount_python_path = "python_path",
		beancount_complete_payee_narration = "complete_payee_narration",
		beancount_fixed_cjk_width = "fixed_cjk_width",
		beancount_flag_warnings = "flag_warnings",
		beancount_inlay_hints = "inlay_hints",
	}

	for vim_var, config_key in pairs(legacy_mappings) do
		if vim.g[vim_var] ~= nil then
			M.options[config_key] = vim.g[vim_var]
		end
	end
end

-- Retrieve configuration value using dot notation
-- @param key string: Configuration key (supports 'parent.child' notation)
-- @return any: Configuration value or nil if not found
M.get = function(key)
	-- Ensure options are initialized with defaults if setup hasn't been called
	if vim.tbl_isempty(M.options) then
		M.options = vim.deepcopy(defaults)
	end

	if key:find("%.") then
		local keys = vim.split(key, "%.", { plain = true })
		local value = M.options
		for _, k in ipairs(keys) do
			value = value[k]
			if value == nil then
				break
			end
		end
		return value
	else
		return M.options[key]
	end
end

-- Set configuration value using dot notation
-- @param key string: Configuration key (supports 'parent.child' notation)
-- @param value any: Value to set
M.set = function(key, value)
	if key:find("%.") then
		local keys = vim.split(key, "%.", { plain = true })
		local target = M.options
		for i = 1, #keys - 1 do
			if target[keys[i]] == nil then
				target[keys[i]] = {}
			end
			target = target[keys[i]]
		end
		target[keys[#keys]] = value
	else
		M.options[key] = value
	end
end

-- Get a deep copy of the entire configuration
-- @return table: Complete configuration table
M.get_all = function()
	return vim.deepcopy(M.options)
end

-- Reset configuration to default values
-- Useful for testing or troubleshooting
M.reset = function()
	M.options = vim.deepcopy(defaults)
end

-- Update configuration at runtime with new options
-- @param opts table: New configuration options to merge
M.update = function(opts)
	M.options = vim.tbl_deep_extend("force", M.options, opts or {})
end

-- Get a copy of the default configuration
-- @return table: Default configuration values (useful for documentation)
M.get_defaults = function()
	return vim.deepcopy(defaults)
end

return M
