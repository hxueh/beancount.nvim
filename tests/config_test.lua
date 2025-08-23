-- Comprehensive functional tests for beancount config module
-- Tests all major functionality without complex test framework

-- Add lua path to find beancount modules
---@diagnostic disable-next-line: redundant-parameter
vim.opt.runtimepath:prepend(vim.fn.getcwd())

print("Running comprehensive config tests...")

local function test_assert(condition, message)
	if not condition then
		error("Test failed: " .. (message or "assertion failed"))
	end
end

local function deep_equal(a, b)
	return vim.deep_equal(a, b)
end

-- Test counter
local tests_run = 0
local tests_passed = 0

local function run_test(name, test_fn)
	tests_run = tests_run + 1
	local success, err = pcall(test_fn)
	if success then
		tests_passed = tests_passed + 1
		print("  ✓ " .. name)
	else
		print("  ✗ " .. name .. ": " .. err)
	end
end

-- Helper to get fresh config module
local function get_config()
	package.loaded["beancount.config"] = nil
	return require("beancount.config")
end

-- Reset vim.g before tests
local original_vim_g = vim.deepcopy(vim.g or {})
vim.g = {}

-- Mock vim.diagnostic.config to avoid errors
vim.diagnostic.config = function() end

-- Test 1: Basic module loading and initialization
run_test("should load config module", function()
	local config = get_config()
	test_assert(type(config) == "table", "config should be a table")
	test_assert(type(config.setup) == "function", "config.setup should be a function")
	test_assert(type(config.get) == "function", "config.get should be a function")
end)

-- Test 2: Empty options initially
run_test("should have empty options initially", function()
	local config = get_config()
	test_assert(deep_equal(config.options, {}), "options should be empty initially")
end)

-- Test 3: Setup with options
run_test("should setup with user options", function()
	local config = get_config()
	config.setup({
		separator_column = 80,
		instant_alignment = false,
	})
	test_assert(config.get("separator_column") == 80, "separator_column should be 80")
	test_assert(config.get("instant_alignment") == false, "instant_alignment should be false")
end)

-- Test 4: Default values
run_test("should provide default values", function()
	local config = get_config()
	local separator_column = config.get("separator_column")
	test_assert(separator_column == 70, "default separator_column should be 70")
end)

-- Test 5: Get defaults
run_test("should return defaults", function()
	local config = get_config()
	local defaults = config.get_defaults()
	test_assert(type(defaults) == "table", "defaults should be a table")
	test_assert(defaults.separator_column == 70, "default separator_column should be 70")
	test_assert(defaults.instant_alignment == true, "default instant_alignment should be true")
end)

-- Test 6: Set values
run_test("should set configuration values", function()
	local config = get_config()
	config.setup({})
	config.set("separator_column", 90)
	test_assert(config.get("separator_column") == 90, "separator_column should be 90 after set")
end)

-- Test 7: Get all configuration
run_test("should return all configuration", function()
	local config = get_config()
	config.setup({ separator_column = 85 })
	local all_config = config.get_all()
	test_assert(all_config.separator_column == 85, "all_config should contain separator_column")
	test_assert(type(all_config) == "table", "all_config should be a table")
end)

-- Test 8: Reset configuration
run_test("should reset configuration to defaults", function()
	local config = get_config()
	config.setup({ separator_column = 100 })
	test_assert(config.get("separator_column") == 100, "separator_column should be 100")
	config.reset()
	test_assert(config.get("separator_column") == 70, "separator_column should be reset to 70")
end)

-- Test 9: Update configuration
run_test("should update configuration", function()
	local config = get_config()
	config.setup({ separator_column = 80, instant_alignment = false })
	config.update({ separator_column = 90 })
	test_assert(config.get("separator_column") == 90, "separator_column should be updated to 90")
	test_assert(config.get("instant_alignment") == false, "instant_alignment should remain false")
end)

-- Test 10: Legacy vim variables
run_test("should load legacy vim global variables", function()
	vim.g.beancount_separator_column = 85
	vim.g.beancount_instant_alignment = false

	local config = get_config()
	config.setup({})

	test_assert(config.get("separator_column") == 85, "should load legacy separator_column")
	test_assert(config.get("instant_alignment") == false, "should load legacy instant_alignment")

	-- Clean up
	vim.g.beancount_separator_column = nil
	vim.g.beancount_instant_alignment = nil
end)

-- Test 11: Nested configuration with dot notation
run_test("should handle nested configuration", function()
	local config = get_config()
	config.setup({
		ui = {
			virtual_text = false,
			signs = true,
		},
	})

	-- The config module should handle nested structures correctly
	local all_config = config.get_all()
	test_assert(all_config.ui ~= nil, "ui configuration should exist")
	test_assert(all_config.ui.virtual_text == false, "ui.virtual_text should be false")
	test_assert(all_config.ui.signs == true, "ui.signs should be true")
end)

-- Test 12: Set nested values with dot notation
run_test("should set nested values with dot notation", function()
	local config = get_config()
	config.setup({})
	config.set("ui.virtual_text", false)
	config.set("nested.deep.value", "test")

	test_assert(config.get("ui.virtual_text") == false, "ui.virtual_text should be false")
	test_assert(config.get("nested.deep.value") == "test", "nested.deep.value should be test")
end)

-- Test 13: Handle nil and empty values
run_test("should handle nil and empty setup gracefully", function()
	local config = get_config()

	-- Test nil setup
	config.setup(nil)
	test_assert(config.get("separator_column") == 70, "should use defaults with nil setup")

	-- Test empty setup
	config.setup({})
	test_assert(config.get("separator_column") == 70, "should use defaults with empty setup")
end)

-- Test 14: Validation (should not crash on invalid inputs)
run_test("should handle validation gracefully", function()
	local config = get_config()

	-- Mock vim.notify to capture warnings
	local notify_called = false
	local old_notify = vim.notify
	---@diagnostic disable-next-line: duplicate-set-field
	vim.notify = function(_, _)
		notify_called = true
	end

	config.setup({
		separator_column = "invalid", -- should trigger validation warning
	})

	vim.notify = old_notify
	test_assert(notify_called, "should call vim.notify for validation errors")
end)

-- Test 15: Configuration keys that don't exist should return nil
run_test("should return nil for non-existent keys", function()
	local config = get_config()
	config.setup({})

	test_assert(config.get("non_existent_key") == nil, "non-existent key should return nil")
	test_assert(config.get("nested.non_existent") == nil, "nested non-existent key should return nil")
end)

-- Restore original vim.g
vim.g = original_vim_g

-- Print summary
print("\nTest Summary:")
print("Tests run: " .. tests_run)
print("Tests passed: " .. tests_passed)
print("Tests failed: " .. (tests_run - tests_passed))

if tests_passed == tests_run then
	print("\n✓ All tests passed!\n")
	vim.cmd("quit")
else
	print("\n✗ Some tests failed!\n")
	vim.cmd("cquit 1")
end
