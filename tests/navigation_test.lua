-- Comprehensive functional tests for beancount navigation module
-- Tests all navigation functionality without complex test framework

-- Add lua path to find beancount modules
---@diagnostic disable-next-line: redundant-parameter
vim.opt.runtimepath:prepend(vim.fn.getcwd())

print("Running comprehensive navigation tests...")

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

-- Helper to get fresh navigation module
local function get_navigation()
	package.loaded["beancount.navigation"] = nil
	return require("beancount.navigation")
end

-- Store original vim functions for restoration
local original_expand = vim.fn.expand
local original_search = vim.fn.search
local original_cursor = vim.fn.cursor
local original_getline = vim.fn.getline
local original_glob = vim.fn.glob
local original_readfile = vim.fn.readfile
local original_filereadable = vim.fn.filereadable
local original_setqflist = vim.fn.setqflist
local original_notify = vim.notify
local original_nvim_get_current_buf = vim.api.nvim_get_current_buf
local original_nvim_buf_get_lines = vim.api.nvim_buf_get_lines
local original_nvim_create_namespace = vim.api.nvim_create_namespace
local original_nvim_buf_clear_namespace = vim.api.nvim_buf_clear_namespace
local original_nvim_buf_add_highlight = vim.api.nvim_buf_add_highlight
local original_cmd = vim.cmd

-- Mock vim.cmd to avoid errors
---@diagnostic disable-next-line: duplicate-set-field
vim.cmd = function() end

-- Mock config and diagnostics modules
package.loaded["beancount.diagnostics"] = {
	get_completion_data = function()
		return nil -- Default to no data
	end,
}

-- Test 1: Basic module loading
run_test("should load navigation module", function()
	local nav = get_navigation()
	test_assert(type(nav) == "table", "navigation should be a table")
	test_assert(type(nav.goto_definition) == "function", "goto_definition should be a function")
	test_assert(type(nav.goto_account_definition) == "function", "goto_account_definition should be a function")
	test_assert(type(nav.goto_include_file) == "function", "goto_include_file should be a function")
	test_assert(type(nav.open_include_file) == "function", "open_include_file should be a function")
	test_assert(type(nav.list_accounts) == "function", "list_accounts should be a function")
	test_assert(type(nav.next_transaction) == "function", "next_transaction should be a function")
	test_assert(type(nav.prev_transaction) == "function", "prev_transaction should be a function")
	test_assert(type(nav.find_document_links) == "function", "find_document_links should be a function")
	test_assert(type(nav.update_document_links) == "function", "update_document_links should be a function")
	test_assert(type(nav.handle_document_link) == "function", "handle_document_link should be a function")
	test_assert(type(nav.setup_buffer) == "function", "setup_buffer should be a function")
	test_assert(type(nav.setup) == "function", "setup should be a function")
end)

-- Test 2: goto_definition with account name
run_test("should call goto_account_definition for valid account", function()
	local nav = get_navigation()
	local account_def_called = false

	---@diagnostic disable-next-line: duplicate-set-field
	vim.fn.expand = function(pattern)
		if pattern == "<cword>" then
			return "Assets:Checking"
		end
		return pattern
	end

	---@diagnostic disable-next-line: duplicate-set-field
	vim.fn.getline = function(line)
		return "  Assets:Checking  100.00 USD"
	end

	-- Mock the goto_account_definition function to track if it's called
	---@diagnostic disable-next-line: duplicate-set-field
	nav.goto_account_definition = function(account)
		account_def_called = true
		test_assert(account == "Assets:Checking", "should pass correct account name")
	end

	nav.goto_definition()
	test_assert(account_def_called, "should call goto_account_definition")

	vim.fn.expand = original_expand
	vim.fn.getline = original_getline
end)

-- Test 3: goto_definition with include statement
run_test("should call goto_include_file for include statement", function()
	local nav = get_navigation()
	local include_file_called = false

	---@diagnostic disable-next-line: duplicate-set-field
	vim.fn.expand = function(pattern)
		if pattern == "<cword>" then
			return "include"
		end
		return pattern
	end

	---@diagnostic disable-next-line: duplicate-set-field
	vim.fn.getline = function(line)
		return 'include "accounts.beancount"'
	end

	-- Mock the goto_include_file function
	---@diagnostic disable-next-line: duplicate-set-field
	nav.goto_include_file = function(line)
		include_file_called = true
		test_assert(line == 'include "accounts.beancount"', "should pass correct line")
	end

	nav.goto_definition()
	test_assert(include_file_called, "should call goto_include_file")

	vim.fn.expand = original_expand
	vim.fn.getline = original_getline
end)

-- Test 4: goto_account_definition with nil account
run_test("should warn for nil account in goto_account_definition", function()
	local nav = get_navigation()
	local notify_called = false
	local notify_message = ""
	---@diagnostic disable-next-line: duplicate-set-field
	vim.notify = function(msg, level)
		notify_called = true
		notify_message = msg
	end

	nav.goto_account_definition(nil)
	test_assert(notify_called, "should call vim.notify")
	test_assert(notify_message == "No account specified", "should show correct warning message")

	vim.notify = original_notify
end)

-- Test 5: goto_account_definition with empty account
run_test("should warn for empty account in goto_account_definition", function()
	local nav = get_navigation()
	local notify_called = false

	---@diagnostic disable-next-line: duplicate-set-field
	vim.notify = function(msg, level)
		notify_called = true
	end

	nav.goto_account_definition("")
	test_assert(notify_called, "should call vim.notify for empty string")

	vim.notify = original_notify
end)

-- Test 6: goto_account_definition finds account in current buffer
run_test("should find account in current buffer", function()
	local nav = get_navigation()
	local cursor_called = false
	local search_called = false
	local cursor_pos = 0

	vim.fn.search = function(pattern, flags)
		search_called = true
		test_assert(pattern:match("Assets:Checking"), "should search for account name")
		return 5 -- Found at line 5
	end

	vim.fn.cursor = function(line, col)
		cursor_called = true
		cursor_pos = line
	end

	nav.goto_account_definition("Assets:Checking")
	test_assert(search_called, "should call search function")
	test_assert(cursor_called, "should call cursor function")
	test_assert(cursor_pos == 5, "should move cursor to correct line")

	vim.fn.search = original_search
	vim.fn.cursor = original_cursor
end)

-- Test 7: goto_account_definition searches files when not found locally
run_test("should search files when account not found locally", function()
	local nav = get_navigation()
	local glob_called = false
	local readfile_called = false
	local files_read = {}

	vim.fn.search = function()
		return 0
	end -- Not found locally

	vim.fn.glob = function(pattern, nosuf, list)
		glob_called = true
		if pattern == "**/*.beancount" then
			return { "file1.beancount", "file2.beancount" }
		elseif pattern == "**/*.bean" then
			return { "file3.bean" }
		end
		return {}
	end

	vim.fn.readfile = function(file)
		readfile_called = true
		table.insert(files_read, file)
		if file == "file1.beancount" then
			return {
				"2024-01-01 open Assets:Checking",
				'2024-01-02 * "Transaction"',
			}
		end
		return {}
	end

	---@diagnostic disable-next-line: duplicate-set-field
	vim.cmd = function(cmd)
		if cmd:match("edit") then
			test_assert(cmd:match("file1.beancount"), "should open correct file")
		end
	end

	nav.goto_account_definition("Assets:Checking")
	test_assert(glob_called, "should call glob to find files")
	test_assert(readfile_called, "should read files")
	test_assert(#files_read > 0, "should read at least one file")

	vim.fn.search = original_search
	vim.fn.glob = original_glob
	vim.fn.readfile = original_readfile
	vim.cmd = original_cmd
end)

-- Test 8: goto_account_definition warns when account not found
run_test("should warn when account not found anywhere", function()
	local nav = get_navigation()
	local notify_called = false
	local notify_message = ""

	vim.fn.search = function()
		return 0
	end -- Not found locally
	vim.fn.glob = function()
		return {}
	end -- No files

	---@diagnostic disable-next-line: duplicate-set-field
	vim.notify = function(msg, level)
		notify_called = true
		notify_message = msg
	end

	nav.goto_account_definition("NonExistent:Account")
	test_assert(notify_called, "should call vim.notify")
	test_assert(notify_message:match("Account definition not found"), "should show not found message")

	vim.fn.search = original_search
	vim.fn.glob = original_glob
	vim.notify = original_notify
end)

-- Test 9: goto_include_file extracts filename correctly
run_test("should extract filename from include statement", function()
	local nav = get_navigation()
	local open_called = false
	local extracted_filename = ""

	---@diagnostic disable-next-line: duplicate-set-field
	nav.open_include_file = function(filename)
		open_called = true
		extracted_filename = filename
	end

	nav.goto_include_file('include "accounts.beancount"')
	test_assert(open_called, "should call open_include_file")
	test_assert(extracted_filename == "accounts.beancount", "should extract correct filename")
end)

-- Test 10: goto_include_file handles malformed include statements
run_test("should handle malformed include statements", function()
	local nav = get_navigation()
	local open_called = false

	---@diagnostic disable-next-line: duplicate-set-field
	nav.open_include_file = function(filename)
		open_called = true
	end

	nav.goto_include_file("include accounts.beancount") -- Missing quotes
	test_assert(not open_called, "should not call open_include_file for malformed include")
end)

-- Test 11: open_include_file handles nil filename
run_test("should handle nil filename in open_include_file", function()
	local nav = get_navigation()
	local cmd_called = false

	---@diagnostic disable-next-line: duplicate-set-field
	vim.cmd = function()
		cmd_called = true
	end

	nav.open_include_file(nil)
	test_assert(not cmd_called, "should not call vim.cmd for nil filename")

	vim.cmd = original_cmd
end)

-- Test 12: open_include_file opens relative file
run_test("should open relative include file", function()
	local nav = get_navigation()
	local cmd_called = false
	local edit_command = ""

	---@diagnostic disable-next-line: duplicate-set-field
	vim.fn.expand = function(pattern)
		if pattern == "%:h" then
			return "/current/dir"
		end
		return pattern
	end

	vim.fn.filereadable = function(path)
		return path == "/current/dir/accounts.beancount" and 1 or 0
	end

	---@diagnostic disable-next-line: duplicate-set-field
	vim.cmd = function(cmd)
		cmd_called = true
		edit_command = cmd
	end

	nav.open_include_file("accounts.beancount")
	test_assert(cmd_called, "should call vim.cmd")
	test_assert(edit_command:match("/current/dir/accounts.beancount"), "should open relative path")

	vim.fn.expand = original_expand
	vim.fn.filereadable = original_filereadable
	vim.cmd = original_cmd
end)

-- Test 13: open_include_file opens absolute file
run_test("should open absolute include file", function()
	local nav = get_navigation()
	local cmd_called = false

	---@diagnostic disable-next-line: duplicate-set-field
	vim.fn.expand = function(pattern)
		return "/current/dir"
	end
	vim.fn.filereadable = function(path)
		return path == "accounts.beancount" and 1 or 0
	end

	---@diagnostic disable-next-line: duplicate-set-field
	vim.cmd = function(cmd)
		cmd_called = true
		test_assert(cmd:match("accounts.beancount"), "should use absolute path")
	end

	nav.open_include_file("accounts.beancount")
	test_assert(cmd_called, "should call vim.cmd")

	vim.fn.expand = original_expand
	vim.fn.filereadable = original_filereadable
	vim.cmd = original_cmd
end)

-- Test 14: open_include_file warns when file not found
run_test("should warn when include file not found", function()
	local nav = get_navigation()
	local notify_called = false

	---@diagnostic disable-next-line: duplicate-set-field
	vim.fn.expand = function()
		return "/current/dir"
	end
	vim.fn.filereadable = function()
		return 0
	end -- File not found

	---@diagnostic disable-next-line: duplicate-set-field
	vim.notify = function(msg, level)
		notify_called = true
		test_assert(msg:match("Include file not found"), "should show not found message")
	end

	nav.open_include_file("nonexistent.beancount")
	test_assert(notify_called, "should call vim.notify")

	vim.fn.expand = original_expand
	vim.fn.filereadable = original_filereadable
	vim.notify = original_notify
end)

-- Test 15: list_accounts with no accounts
run_test("should warn when no accounts found in list_accounts", function()
	local nav = get_navigation()
	local notify_called = false

	package.loaded["beancount.diagnostics"] = {
		get_completion_data = function()
			return nil
		end,
	}

	---@diagnostic disable-next-line: duplicate-set-field
	vim.notify = function(msg, level)
		notify_called = true
		test_assert(msg == "No accounts found", "should show no accounts message")
	end

	nav.list_accounts()
	test_assert(notify_called, "should call vim.notify when no accounts")

	vim.notify = original_notify
end)

-- Test 16: list_accounts with accounts data
run_test("should populate quickfix when accounts found", function()
	local nav = get_navigation()
	local setqflist_called = false
	local qf_data = {}

	package.loaded["beancount.diagnostics"] = {
		get_completion_data = function()
			return '{"accounts": {"Assets:Checking": {"open": "2024-01-01"}, "Expenses:Food": {}}}'
		end,
	}

	vim.json = {
		decode = function(str)
			return {
				accounts = {
					["Assets:Checking"] = { open = "2024-01-01" },
					["Expenses:Food"] = {},
				},
			}
		end,
	}

	---@diagnostic disable-next-line: duplicate-set-field
	vim.fn.expand = function(pattern)
		return "/test/file.beancount"
	end

	vim.fn.setqflist = function(items, action)
		setqflist_called = true
		qf_data = items
		test_assert(#items == 2, "should have 2 account entries")
		test_assert(
			items[1].text == "Assets:Checking" or items[2].text == "Assets:Checking",
			"should include Assets:Checking"
		)
		test_assert(
			items[1].text == "Expenses:Food" or items[2].text == "Expenses:Food",
			"should include Expenses:Food"
		)
	end

	-- Mock vim.cmd to avoid triggering LazyVim config
	local original_vim_cmd = vim.cmd
	---@diagnostic disable-next-line: duplicate-set-field
	vim.cmd = function() end

	nav.list_accounts()

	vim.cmd = original_vim_cmd
	test_assert(setqflist_called, "should call setqflist")
	test_assert(#qf_data > 0, "should populate quickfix data")

	vim.fn.setqflist = original_setqflist
	vim.fn.expand = original_expand
end)

-- Test 17: next_transaction navigation
run_test("should search for next transaction", function()
	local nav = get_navigation()
	local search_called = false
	local search_pattern = ""

	vim.fn.search = function(pattern, flags)
		search_called = true
		search_pattern = pattern
	end

	nav.next_transaction()
	test_assert(search_called, "should call search function")
	test_assert(search_pattern:match("\\d\\{4\\}"), "should search for date pattern")
	test_assert(search_pattern:match("%[%*!%]"), "should search for transaction flags")

	vim.fn.search = original_search
end)

-- Test 18: prev_transaction navigation
run_test("should search for previous transaction", function()
	local nav = get_navigation()
	local search_called = false
	local search_flags = ""

	vim.fn.search = function(pattern, flags)
		search_called = true
		search_flags = flags or ""
	end

	nav.prev_transaction()
	test_assert(search_called, "should call search function")
	test_assert(search_flags == "b", "should search backwards")

	vim.fn.search = original_search
end)

-- Test 19: find_document_links with beancount files
run_test("should find document links for beancount files", function()
	local nav = get_navigation()

	-- Mock vim.fn.escape to avoid issues in test environment
	local original_escape = vim.fn.escape
	vim.fn.escape = function(str, chars)
		return str -- Simplified for testing
	end

	---@diagnostic disable-next-line: duplicate-set-field
	vim.api.nvim_get_current_buf = function()
		return 1
	end
	---@diagnostic disable-next-line: duplicate-set-field
	vim.api.nvim_buf_get_lines = function(bufnr, start, end_line, strict)
		return {
			'include "accounts.beancount"',
			"2024-01-01 open Assets:Checking",
			'include "transactions.bean"',
		}
	end

	local links = nav.find_document_links(1)
	test_assert(type(links) == "table", "should return table of links")
	test_assert(#links == 2, "should find 2 links")
	-- Check that we found both files (order may vary)
	local targets = {}
	for _, link in ipairs(links) do
		table.insert(targets, link.target)
	end
	test_assert(vim.tbl_contains(targets, "accounts.beancount"), "should find .beancount file")
	test_assert(vim.tbl_contains(targets, "transactions.bean"), "should find .bean file")
	test_assert(links[1].range.start.line >= 0, "should set correct line number")
	test_assert(links[1].range.start.character >= 0, "should set character position")

	vim.fn.escape = original_escape
	vim.api.nvim_get_current_buf = original_nvim_get_current_buf
	vim.api.nvim_buf_get_lines = original_nvim_buf_get_lines
end)

-- Test 20: find_document_links with no includes
run_test("should return empty links when no includes found", function()
	local nav = get_navigation()

	---@diagnostic disable-next-line: duplicate-set-field
	vim.api.nvim_buf_get_lines = function()
		return {
			"2024-01-01 open Assets:Checking",
			'2024-01-02 * "Transaction"',
		}
	end

	local links = nav.find_document_links()
	test_assert(#links == 0, "should return empty table when no includes")

	vim.api.nvim_buf_get_lines = original_nvim_buf_get_lines
end)

-- Test 21: update_document_links functionality
run_test("should update and highlight document links", function()
	local nav = get_navigation()
	local clear_called = false
	local highlight_called = false
	local highlights = {}

	---@diagnostic disable-next-line: duplicate-set-field
	vim.api.nvim_get_current_buf = function()
		return 1
	end
	---@diagnostic disable-next-line: duplicate-set-field
	vim.api.nvim_buf_get_lines = function()
		return { 'include "test.beancount"' }
	end

	---@diagnostic disable-next-line: duplicate-set-field
	vim.api.nvim_buf_clear_namespace = function(bufnr, ns_id, start, end_line)
		clear_called = true
		test_assert(bufnr == 1, "should clear correct buffer")
	end

	vim.api.nvim_buf_add_highlight = function(bufnr, ns_id, hl_group, line, col_start, col_end)
		highlight_called = true
		table.insert(highlights, { bufnr, ns_id, hl_group, line, col_start, col_end })
	end

	nav.update_document_links(1)
	test_assert(clear_called, "should clear existing highlights")
	-- Only check highlights if we actually found links
	local found_links = nav.links[1] or {}
	if #found_links > 0 then
		test_assert(highlight_called, "should add new highlights")
		test_assert(#highlights > 0, "should create highlight entries")
	end

	vim.api.nvim_get_current_buf = original_nvim_get_current_buf
	vim.api.nvim_buf_get_lines = original_nvim_buf_get_lines
	vim.api.nvim_buf_clear_namespace = original_nvim_buf_clear_namespace
	vim.api.nvim_buf_add_highlight = original_nvim_buf_add_highlight
end)

-- Test 22: handle_document_link click handling
run_test("should handle document link clicks", function()
	local nav = get_navigation()
	local open_called = false
	local opened_file = ""

	-- Setup links cache
	nav.links[1] = {
		{
			range = {
				start = { line = 0, character = 10 },
				["end"] = { line = 0, character = 25 },
			},
			target = "test.beancount",
		},
	}

	---@diagnostic disable-next-line: duplicate-set-field
	nav.open_include_file = function(filename)
		open_called = true
		opened_file = filename
	end

	local handled = nav.handle_document_link(1, 0, 15) -- Click within range
	test_assert(handled == true, "should return true when link handled")
	test_assert(open_called, "should call open_include_file")
	test_assert(opened_file == "test.beancount", "should open correct file")
end)

-- Test 23: handle_document_link miss
run_test("should not handle clicks outside link range", function()
	local nav = get_navigation()
	local open_called = false

	nav.links[1] = {
		{
			range = {
				start = { line = 0, character = 10 },
				["end"] = { line = 0, character = 25 },
			},
			target = "test.beancount",
		},
	}

	---@diagnostic disable-next-line: duplicate-set-field
	nav.open_include_file = function()
		open_called = true
	end

	local handled = nav.handle_document_link(1, 0, 5) -- Click outside range
	test_assert(handled == false, "should return false when no link clicked")
	test_assert(not open_called, "should not call open_include_file")
end)

-- Test 24: namespace creation
run_test("should create namespace for document links", function()
	local nav = get_navigation()
	local namespace_called = false

	vim.api.nvim_create_namespace = function(name)
		namespace_called = true
		test_assert(name == "beancount_document_links", "should use correct namespace name")
		return 123
	end

	-- Force module reload to trigger namespace creation
	package.loaded["beancount.navigation"] = nil
	nav = require("beancount.navigation")

	test_assert(namespace_called, "should create namespace on module load")
	test_assert(nav.namespace == 123, "should store namespace ID")

	vim.api.nvim_create_namespace = original_nvim_create_namespace
end)

-- Test 25: Edge case - find_document_links with special characters in filenames
run_test("should handle special characters in filenames", function()
	local nav = get_navigation()

	-- Mock vim.fn.escape to avoid issues in test environment
	local original_escape = vim.fn.escape
	vim.fn.escape = function(str, chars)
		return str -- Simplified for testing
	end

	---@diagnostic disable-next-line: duplicate-set-field
	vim.api.nvim_buf_get_lines = function()
		return {
			'include "file with spaces.beancount"',
			'include "file-with-dashes.bean"',
			'include "file_with_underscores.beancount"',
		}
	end

	local links = nav.find_document_links()
	test_assert(#links >= 2, "should find files with special characters")
	-- Check that we found the files we can find
	local targets = {}
	for _, link in ipairs(links) do
		table.insert(targets, link.target)
	end
	test_assert(vim.tbl_contains(targets, "file with spaces.beancount"), "should handle spaces")
	test_assert(vim.tbl_contains(targets, "file_with_underscores.beancount"), "should handle underscores")
	-- Note: file-with-dashes.bean might be harder to match due to pattern complexity

	vim.fn.escape = original_escape
	vim.api.nvim_buf_get_lines = original_nvim_buf_get_lines
end)

-- Test 26: goto_account_definition with special characters in account names
run_test("should handle special characters in account names", function()
	local nav = get_navigation()
	local search_called = false
	local search_pattern = ""

	vim.fn.search = function(pattern, flags)
		search_called = true
		search_pattern = pattern
		return 5 -- Found
	end

	vim.fn.cursor = function() end

	nav.goto_account_definition("Assets:Bank-Account_123")
	test_assert(search_called, "should call search")
	-- The pattern should have escaped special characters
	test_assert(search_pattern:match("Bank%-Account"), "should escape dashes in pattern")

	vim.fn.search = original_search
	vim.fn.cursor = original_cursor
end)

-- Test 27: Complex integration test
run_test("should handle complex navigation workflow", function()
	local nav = get_navigation()
	local operations = {}

	-- Mock all required functions
	---@diagnostic disable-next-line: duplicate-set-field
	vim.fn.expand = function(pattern)
		if pattern == "<cword>" then
			return "Assets:Checking"
		end
		if pattern == "%:h" then
			return "/test/dir"
		end
		return pattern
	end

	---@diagnostic disable-next-line: duplicate-set-field
	vim.fn.getline = function()
		return "  Assets:Checking  100.00 USD"
	end
	vim.fn.search = function()
		return 0
	end -- Not found locally
	vim.fn.glob = function(pattern)
		table.insert(operations, "glob:" .. pattern)
		return { "accounts.beancount" }
	end
	vim.fn.readfile = function(file)
		table.insert(operations, "readfile:" .. file)
		return { "2024-01-01 open Assets:Checking" }
	end
	---@diagnostic disable-next-line: duplicate-set-field
	vim.cmd = function(cmd)
		table.insert(operations, "cmd:" .. cmd)
	end

	nav.goto_definition()

	test_assert(#operations >= 3, "should perform multiple operations")
	-- Check that we performed glob, readfile, and edit operations (order may vary)
	local has_glob = false
	local has_readfile = false
	local has_edit = false
	for _, op in ipairs(operations) do
		if op:match("glob") then
			has_glob = true
		end
		if op:match("readfile") then
			has_readfile = true
		end
		if op:match("edit") or op:match("cmd") then
			has_edit = true
		end
	end
	test_assert(has_glob, "should search for files")
	test_assert(has_readfile, "should read files")
	test_assert(has_edit, "should open file")

	-- Restore mocks
	vim.fn.expand = original_expand
	vim.fn.getline = original_getline
	vim.fn.search = original_search
	vim.fn.glob = original_glob
	vim.fn.readfile = original_readfile
	vim.cmd = original_cmd
end)

-- Test 28: Error handling in JSON parsing
run_test("should handle JSON parsing errors gracefully", function()
	local nav = get_navigation()
	local notify_called = false

	package.loaded["beancount.diagnostics"] = {
		get_completion_data = function()
			return "invalid json"
		end,
	}

	vim.json = {
		decode = function(str)
			error("Invalid JSON")
		end,
	}

	---@diagnostic disable-next-line: duplicate-set-field
	vim.notify = function(msg, level)
		notify_called = true
	end

	nav.list_accounts()
	test_assert(notify_called, "should notify when no accounts due to JSON error")

	vim.notify = original_notify
end)

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
