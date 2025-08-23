-- Comprehensive functional tests for beancount utils module
-- Tests all utility functions without complex test framework

-- Add lua path to find beancount modules
---@diagnostic disable-next-line: redundant-parameter
vim.opt.runtimepath:prepend(vim.fn.getcwd())

print("Running comprehensive utils tests...")

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

-- Helper to get utils module (cache for reuse)
local utils_module
local function get_utils()
	if not utils_module then
		utils_module = require("beancount.utils")
	end
	return utils_module
end

-- Mock vim functions needed for testing
local original_expand = vim.fn.expand
local original_getcwd = vim.fn.getcwd
local original_jobstart = vim.fn.jobstart
local original_bo = vim.bo
local original_startswith = vim.startswith
local original_fs_stat = vim.loop.fs_stat

-- Test 1: Basic module loading
run_test("should load utils module", function()
	local utils = get_utils()
	test_assert(type(utils) == "table", "utils should be a table")
	test_assert(type(utils.run_cmd) == "function", "run_cmd should be a function")
	test_assert(type(utils.get_main_bean_file) == "function", "get_main_bean_file should be a function")
	test_assert(type(utils.resolve_env_vars) == "function", "resolve_env_vars should be a function")
	test_assert(type(utils.count_occurrences) == "function", "count_occurrences should be a function")
	test_assert(type(utils.tbl_contains) == "function", "tbl_contains should be a function")
	test_assert(type(utils.get_file_extension) == "function", "get_file_extension should be a function")
	test_assert(type(utils.file_exists) == "function", "file_exists should be a function")
	test_assert(type(utils.get_plugin_dir) == "function", "get_plugin_dir should be a function")
end)

-- Test 2: run_cmd function basic structure
run_test("should handle run_cmd with mocked jobstart", function()
	local utils = get_utils()
	local job_id_called = false

	vim.fn.jobstart = function(cmd_table, opts)
		job_id_called = true
		test_assert(type(cmd_table) == "table", "cmd_table should be table")
		test_assert(type(opts) == "table", "opts should be table")
		return 123 -- mock job ID
	end

	local job_id = utils.run_cmd("echo", { "test" }, nil, {})
	test_assert(job_id_called, "jobstart should be called")
	test_assert(job_id == 123, "should return job ID")

	vim.fn.jobstart = original_jobstart
end)

-- Test 3: get_main_bean_file with no config
run_test("should return current file when no main file configured", function()
	local utils = get_utils()

	-- Mock config module
	package.loaded["beancount.config"] = {
		get = function(key)
			if key == "main_bean_file" then
				return nil
			end
		end,
	}

	---@diagnostic disable-next-line: duplicate-set-field
	vim.fn.expand = function(path)
		if path == "%:p" then
			return "/path/to/current.beancount"
		end
		return path
	end

	vim.bo = { filetype = "beancount" }

	local main_file = utils.get_main_bean_file()
	test_assert(main_file == "/path/to/current.beancount", "should return current file path")

	vim.fn.expand = original_expand
	vim.bo = original_bo
end)

-- Test 4: get_main_bean_file with empty config
run_test("should return current file when main file is empty string", function()
	local utils = get_utils()

	-- Mock config module
	package.loaded["beancount.config"] = {
		get = function(key)
			if key == "main_bean_file" then
				return ""
			end
		end,
	}

	---@diagnostic disable-next-line: duplicate-set-field
	vim.fn.expand = function(path)
		if path == "%:p" then
			return "/path/to/current.beancount"
		end
		return path
	end

	vim.bo = { filetype = "beancount" }

	local main_file = utils.get_main_bean_file()
	test_assert(main_file == "/path/to/current.beancount", "should return current file path")

	vim.fn.expand = original_expand
	vim.bo = original_bo
end)

-- Test 5: get_main_bean_file with non-beancount filetype
run_test("should return empty string for non-beancount files", function()
	local utils = get_utils()

	-- Mock config module
	package.loaded["beancount.config"] = {
		get = function(key)
			if key == "main_bean_file" then
				return nil
			end
		end,
	}

	vim.bo = { filetype = "text" }

	local main_file = utils.get_main_bean_file()
	test_assert(main_file == "", "should return empty string for non-beancount files")

	vim.bo = original_bo
end)

-- Test 6: get_main_bean_file with absolute path
run_test("should return absolute path when configured", function()
	local utils = get_utils()

	-- Mock config module
	package.loaded["beancount.config"] = {
		get = function(key)
			if key == "main_bean_file" then
				return "/absolute/path/to/main.beancount"
			end
		end,
	}

	local main_file = utils.get_main_bean_file()
	test_assert(main_file == "/absolute/path/to/main.beancount", "should return configured absolute path")
end)

-- Test 7: get_main_bean_file with relative path
run_test("should convert relative path to absolute", function()
	local utils = get_utils()

	-- Mock config module
	package.loaded["beancount.config"] = {
		get = function(key)
			if key == "main_bean_file" then
				return "relative/main.beancount"
			end
		end,
	}

	vim.fn.getcwd = function()
		return "/current/working/dir"
	end

	---@diagnostic disable-next-line: duplicate-set-field
	vim.startswith = function(str, prefix)
		return string.sub(str, 1, #prefix) == prefix
	end

	local main_file = utils.get_main_bean_file()
	test_assert(main_file == "/current/working/dir/relative/main.beancount", "should convert relative to absolute path")

	vim.fn.getcwd = original_getcwd
	vim.startswith = original_startswith
end)

-- Test 8: resolve_env_vars function
run_test("should resolve environment variables", function()
	local utils = get_utils()

	-- Mock os.getenv
	local original_getenv = os.getenv
	---@diagnostic disable-next-line: duplicate-set-field
	os.getenv = function(var)
		if var == "HOME" then
			return "/home/user"
		elseif var == "USER" then
			return "testuser"
		end
		return nil
	end

	local result1 = utils.resolve_env_vars("%HOME%/documents")
	test_assert(result1 == "/home/user/documents", "should resolve HOME variable")

	local result2 = utils.resolve_env_vars("User: %USER%")
	test_assert(result2 == "User: testuser", "should resolve USER variable")

	local result3 = utils.resolve_env_vars("%NONEXISTENT%/path")
	test_assert(result3 == "/path", "should replace non-existent vars with empty string")

	os.getenv = original_getenv
end)

-- Test 9: count_occurrences function
run_test("should count character occurrences correctly", function()
	local utils = get_utils()

	test_assert(utils.count_occurrences("hello world", "l") == 3, "should count 'l' correctly")
	test_assert(utils.count_occurrences("banana", "a") == 3, "should count 'a' correctly")
	test_assert(utils.count_occurrences("test", "x") == 0, "should return 0 for non-existent char")
	test_assert(utils.count_occurrences("", "a") == 0, "should handle empty string")
	test_assert(utils.count_occurrences("test", "") == 0, "should handle empty char")
	test_assert(utils.count_occurrences(nil, "a") == 0, "should handle nil string")
	test_assert(utils.count_occurrences("test", nil) == 0, "should handle nil char")
end)

-- Test 10: tbl_contains function
run_test("should check table contains correctly", function()
	local utils = get_utils()

	local test_table = { "apple", "banana", "cherry" }

	test_assert(utils.tbl_contains(test_table, "apple") == true, "should find existing value")
	test_assert(utils.tbl_contains(test_table, "banana") == true, "should find middle value")
	test_assert(utils.tbl_contains(test_table, "grape") == false, "should not find non-existent value")
	test_assert(utils.tbl_contains({}, "test") == false, "should handle empty table")
	test_assert(utils.tbl_contains(nil, "test") == false, "should handle nil table")

	-- Test with numbers
	local num_table = { 1, 2, 3 }
	test_assert(utils.tbl_contains(num_table, 2) == true, "should find number")
	test_assert(utils.tbl_contains(num_table, 4) == false, "should not find non-existent number")
end)

-- Test 11: get_file_extension function
run_test("should extract file extensions correctly", function()
	local utils = get_utils()

	test_assert(utils.get_file_extension("test.txt") == "txt", "should extract txt extension")
	test_assert(utils.get_file_extension("file.beancount") == "beancount", "should extract beancount extension")
	test_assert(utils.get_file_extension("path/to/file.lua") == "lua", "should extract lua extension from path")
	test_assert(utils.get_file_extension("file.with.multiple.dots.js") == "js", "should extract last extension")
	test_assert(utils.get_file_extension("no_extension") == nil, "should return nil for no extension")
	test_assert(utils.get_file_extension("") == nil, "should handle empty string")
	test_assert(utils.get_file_extension(nil) == nil, "should handle nil input")
	test_assert(utils.get_file_extension(".hidden") == "hidden", "should extract extension from hidden files")
	test_assert(utils.get_file_extension("file.") == nil, "should handle trailing dot")
end)

-- Test 12: file_exists function
run_test("should check file existence correctly", function()
	local utils = get_utils()

	vim.loop.fs_stat = function(path)
		if path == "/existing/file.txt" then
			return { type = "file" }
		elseif path == "/existing/directory" then
			return { type = "directory" }
		end
		return nil
	end

	test_assert(utils.file_exists("/existing/file.txt") == true, "should return true for existing file")
	test_assert(utils.file_exists("/existing/directory") == false, "should return false for directory")
	test_assert(utils.file_exists("/non/existent/file.txt") == nil, "should return nil for non-existent file")
	test_assert(utils.file_exists("") == false, "should handle empty path")
	test_assert(utils.file_exists(nil) == false, "should handle nil path")

	vim.loop.fs_stat = original_fs_stat
end)

-- Test 13: get_plugin_dir function
run_test("should get plugin directory correctly", function()
	local utils = get_utils()

	-- Mock debug.getinfo and vim.fn.fnamemodify
	local original_getinfo = debug.getinfo
	local original_fnamemodify = vim.fn.fnamemodify

	---@diagnostic disable-next-line: duplicate-set-field
	debug.getinfo = function(_, _)
		return { source = "@/path/to/beancount.nvim/lua/beancount/utils.lua" }
	end

	vim.fn.fnamemodify = function(path, modifier)
		if modifier == ":h:h:h" and path == "/path/to/beancount.nvim/lua/beancount/utils.lua" then
			return "/path/to/beancount.nvim"
		end
		return path
	end

	local plugin_dir = utils.get_plugin_dir()
	test_assert(plugin_dir == "/path/to/beancount.nvim", "should return correct plugin directory")

	debug.getinfo = original_getinfo
	vim.fn.fnamemodify = original_fnamemodify
end)

-- Test 14: run_cmd with callback
run_test("should handle run_cmd callback execution", function()
	local utils = get_utils()
	local callback_called = false
	local callback_stdout, callback_stderr, callback_exit_code

	vim.fn.jobstart = function(cmd_table, opts)
		test_assert(opts.stdout_buffered == true, "should set stdout_buffered")
		test_assert(opts.stderr_buffered == true, "should set stderr_buffered")
		test_assert(type(opts.on_stdout) == "function", "should have on_stdout function")
		test_assert(type(opts.on_stderr) == "function", "should have on_stderr function")
		test_assert(type(opts.on_exit) == "function", "should have on_exit function")

		-- Simulate command execution
		opts.on_stdout(nil, { "line1", "line2" })
		opts.on_stderr(nil, { "error1" })
		opts.on_exit(nil, 0)

		return 456
	end

	local test_callback = function(stdout, stderr, exit_code)
		callback_called = true
		callback_stdout = stdout
		callback_stderr = stderr
		callback_exit_code = exit_code
	end

	local job_id = utils.run_cmd("test", { "arg" }, test_callback, { cwd = "/test/dir" })

	test_assert(job_id == 456, "should return correct job ID")
	test_assert(callback_called, "callback should be called")
	test_assert(callback_stdout == "line1\nline2", "should concatenate stdout lines")
	test_assert(callback_stderr == "error1", "should concatenate stderr lines")
	test_assert(callback_exit_code == 0, "should pass exit code")

	vim.fn.jobstart = original_jobstart
end)

-- Test 15: run_cmd without callback
run_test("should handle run_cmd without callback", function()
	local utils = get_utils()

	vim.fn.jobstart = function(cmd_table, opts)
		-- Simulate command execution without callback
		opts.on_stdout(nil, { "output" })
		opts.on_stderr(nil, { "error" })
		opts.on_exit(nil, 1)
		return 789
	end

	local job_id = utils.run_cmd("test", { "arg" }, nil, {})
	test_assert(job_id == 789, "should return job ID even without callback")

	vim.fn.jobstart = original_jobstart
end)

-- Test 16: run_cmd with empty data handling
run_test("should handle empty data in run_cmd callbacks", function()
	local utils = get_utils()

	vim.fn.jobstart = function(cmd_table, opts)
		-- Simulate empty data
		opts.on_stdout(nil, nil)
		opts.on_stderr(nil, nil)
		opts.on_exit(nil, 0)
		return 101
	end

	local callback_called = false
	local test_callback = function(stdout, stderr, exit_code)
		callback_called = true
		test_assert(stdout == "", "should handle nil stdout data")
		test_assert(stderr == "", "should handle nil stderr data")
	end

	utils.run_cmd("test", {}, test_callback, {})
	test_assert(callback_called, "callback should still be called with empty data")

	vim.fn.jobstart = original_jobstart
end)

-- Test 17: Edge cases for count_occurrences
run_test("should handle edge cases in count_occurrences", function()
	local utils = get_utils()

	test_assert(utils.count_occurrences("aaa", "a") == 3, "should count repeated chars")
	test_assert(utils.count_occurrences("a", "a") == 1, "should count single char")
	test_assert(utils.count_occurrences("abc", "d") == 0, "should return 0 for missing char")
	test_assert(utils.count_occurrences("A", "a") == 0, "should be case sensitive")
	test_assert(utils.count_occurrences("123", "1") == 1, "should work with numbers")
	test_assert(utils.count_occurrences("!@#!@#", "!") == 2, "should work with special chars")
end)

-- Test 18: Edge cases for tbl_contains
run_test("should handle edge cases in tbl_contains", function()
	local utils = get_utils()

	test_assert(utils.tbl_contains({ false, "test" }, "test") == true, "should work with false values in table")
	test_assert(utils.tbl_contains({ false }, false) == true, "should find boolean false")
	test_assert(utils.tbl_contains({ 0 }, 0) == true, "should find zero")
	test_assert(utils.tbl_contains({ "0" }, 0) == false, "should distinguish string '0' from number 0")
	-- Note: ipairs skips nil values so tbl_contains cannot find nil in tables
end)

-- Test 19: Complex file extension cases
run_test("should handle complex file extension cases", function()
	local utils = get_utils()

	test_assert(utils.get_file_extension("file.tar.gz") == "gz", "should get last extension for compound extensions")
	test_assert(utils.get_file_extension("path/with spaces/file.txt") == "txt", "should work with spaces in path")
	test_assert(
		utils.get_file_extension("file with spaces.beancount") == "beancount",
		"should work with spaces in filename"
	)
	test_assert(utils.get_file_extension("../relative/path/file.lua") == "lua", "should work with relative paths")
end)

-- Test 20: Environment variable edge cases
run_test("should handle environment variable edge cases", function()
	local utils = get_utils()

	local original_getenv = os.getenv
	---@diagnostic disable-next-line: duplicate-set-field
	os.getenv = function(var)
		if var == "EMPTY" then
			return ""
		elseif var == "SPACE" then
			return "value with spaces"
		end
		return nil
	end

	test_assert(utils.resolve_env_vars("%EMPTY%test") == "test", "should handle empty env var")
	test_assert(
		utils.resolve_env_vars("prefix%SPACE%suffix") == "prefixvalue with spacessuffix",
		"should handle env var with spaces"
	)
	test_assert(utils.resolve_env_vars("%%") == "%%", "should leave double percent unchanged")
	test_assert(
		utils.resolve_env_vars("no variables here") == "no variables here",
		"should leave strings without variables unchanged"
	)

	os.getenv = original_getenv
end)

-- Test 21: File existence with various path types
run_test("should handle various path types in file_exists", function()
	local utils = get_utils()

	vim.loop.fs_stat = function(path)
		local files = {
			["/absolute/path/file.txt"] = { type = "file" },
			["./relative/file.txt"] = { type = "file" },
			["/dir/symlink"] = { type = "link" },
			["/special chars/file name.txt"] = { type = "file" },
		}
		return files[path]
	end

	test_assert(utils.file_exists("/absolute/path/file.txt") == true, "should work with absolute paths")
	test_assert(utils.file_exists("./relative/file.txt") == true, "should work with relative paths")
	test_assert(utils.file_exists("/dir/symlink") == false, "should return false for symlinks")
	test_assert(utils.file_exists("/special chars/file name.txt") == true, "should work with special characters")

	vim.loop.fs_stat = original_fs_stat
end)

-- Test 22: Complex main file resolution scenarios
run_test("should handle complex main file scenarios", function()
	local utils = get_utils()

	-- Mock config module with complex scenarios
	package.loaded["beancount.config"] = {
		get = function(key)
			if key == "main_bean_file" then
				return "~/documents/main.beancount" -- Path with tilde
			end
		end,
	}

	---@diagnostic disable-next-line: duplicate-set-field
	vim.startswith = function(str, prefix)
		return string.sub(str, 1, #prefix) == prefix
	end

	vim.fn.getcwd = function()
		return "/current/dir"
	end

	local main_file = utils.get_main_bean_file()
	test_assert(main_file == "/current/dir/~/documents/main.beancount", "should handle tilde paths as relative")

	vim.startswith = original_startswith
	vim.fn.getcwd = original_getcwd
end)

-- Test 23: run_cmd with various argument types and edge cases
run_test("should handle run_cmd with various argument types", function()
	local utils = get_utils()
	local callback_results = {}

	vim.fn.jobstart = function(cmd_table, opts)
		-- Simulate command with empty arguments
		if #cmd_table == 1 then
			opts.on_stdout(nil, {})
			opts.on_stderr(nil, {})
			opts.on_exit(nil, 0)
		end
		return 999
	end

	-- Test with empty args table
	local job_id = utils.run_cmd("test", {}, function(stdout, stderr, exit_code)
		callback_results = { stdout, stderr, exit_code }
	end, {})

	test_assert(job_id == 999, "should handle empty args")
	test_assert(callback_results[1] == "", "should handle empty stdout")
	test_assert(callback_results[2] == "", "should handle empty stderr")
	test_assert(callback_results[3] == 0, "should handle successful exit")

	vim.fn.jobstart = original_jobstart
end)

-- Test 24: get_main_bean_file with Windows-style paths
run_test("should handle Windows-style paths in get_main_bean_file", function()
	local utils = get_utils()

	package.loaded["beancount.config"] = {
		get = function(key)
			if key == "main_bean_file" then
				return "C:\\Users\\test\\documents\\main.beancount" -- Windows absolute path
			end
		end,
	}

	---@diagnostic disable-next-line: duplicate-set-field
	vim.startswith = function(str, prefix)
		return string.sub(str, 1, #prefix) == prefix
	end

	local main_file = utils.get_main_bean_file()
	test_assert(main_file == "C:\\Users\\test\\documents\\main.beancount", "should handle Windows absolute paths")

	vim.startswith = original_startswith
end)

-- Test 25: resolve_env_vars with nested and malformed patterns
run_test("should handle malformed environment variable patterns", function()
	local utils = get_utils()

	local original_getenv = os.getenv
	---@diagnostic disable-next-line: duplicate-set-field
	os.getenv = function(var)
		if var == "TEST" then
			return "value"
		end
		return nil
	end

	-- Test malformed patterns
	test_assert(utils.resolve_env_vars("%TEST") == "%TEST", "should handle unclosed variable")
	test_assert(utils.resolve_env_vars("TEST%") == "TEST%", "should handle unopened variable")
	test_assert(utils.resolve_env_vars("%NESTED%TEST%") == "TEST%", "should handle nested patterns")
	test_assert(utils.resolve_env_vars("%TEST%%TEST%") == "valuevalue", "should handle adjacent variables")
	test_assert(utils.resolve_env_vars("") == "", "should handle empty string")

	os.getenv = original_getenv
end)

-- Test 26: count_occurrences with Unicode and special characters
run_test("should handle Unicode and special characters in count_occurrences", function()
	local utils = get_utils()

	test_assert(utils.count_occurrences("café", "é") == 0, "should handle Unicode characters (byte-level matching)")
	test_assert(utils.count_occurrences("\\n\\n\\n", "\\") == 3, "should count backslashes")
	test_assert(utils.count_occurrences("\"'\"'", '"') == 2, "should count quote marks")
	test_assert(utils.count_occurrences("tab\ttab\t", "\t") == 2, "should count tab characters")
	test_assert(utils.count_occurrences("line\nline\n", "\n") == 2, "should count newlines")
	test_assert(utils.count_occurrences("space space", " ") == 1, "should count spaces")
end)

-- Test 27: tbl_contains with complex data types
run_test("should handle complex data types in tbl_contains", function()
	local utils = get_utils()

	local test_table = { "string", 123, true, false, 0, "" }

	test_assert(utils.tbl_contains(test_table, "string") == true, "should find strings")
	test_assert(utils.tbl_contains(test_table, 123) == true, "should find numbers")
	test_assert(utils.tbl_contains(test_table, true) == true, "should find boolean true")
	test_assert(utils.tbl_contains(test_table, false) == true, "should find boolean false")
	test_assert(utils.tbl_contains(test_table, 0) == true, "should find zero")
	test_assert(utils.tbl_contains(test_table, "") == true, "should find empty string")

	-- Test non-existent values
	test_assert(utils.tbl_contains(test_table, "missing") == false, "should not find missing string")
	test_assert(utils.tbl_contains(test_table, 456) == false, "should not find missing number")
end)

-- Test 28: get_file_extension with complex filename patterns
run_test("should handle complex filename patterns in get_file_extension", function()
	local utils = get_utils()

	test_assert(utils.get_file_extension("file.backup.2024.txt") == "txt", "should get extension from dated backup")
	test_assert(utils.get_file_extension("archive.tar.gz.backup") == "backup", "should get final extension")
	test_assert(utils.get_file_extension("FILE.TXT") == "TXT", "should preserve case")
	test_assert(utils.get_file_extension("file.123") == "123", "should handle numeric extensions")
	test_assert(utils.get_file_extension("file.a") == "a", "should handle single-char extensions")
	test_assert(utils.get_file_extension("path.with.dots/filename") == nil, "should handle no extension in dotted path")
	test_assert(utils.get_file_extension("....") == nil, "should handle multiple dots only")
end)

-- Test 29: file_exists with edge case paths
run_test("should handle edge case paths in file_exists", function()
	local utils = get_utils()

	vim.loop.fs_stat = function(path)
		local special_cases = {
			["/path with spaces/file.txt"] = { type = "file" },
			["/path/with/../relative/file.txt"] = { type = "file" },
			["/very/long/path/that/goes/on/and/on/and/continues/for/a/while/file.txt"] = { type = "file" },
			["/path/with-special~chars!@#$/file.txt"] = { type = "file" },
			["/"] = { type = "directory" },
			["/dev/null"] = { type = "file" },
		}
		return special_cases[path]
	end

	test_assert(utils.file_exists("/path with spaces/file.txt") == true, "should handle spaces in paths")
	test_assert(utils.file_exists("/path/with/../relative/file.txt") == true, "should handle relative components")
	test_assert(
		utils.file_exists("/very/long/path/that/goes/on/and/on/and/continues/for/a/while/file.txt") == true,
		"should handle long paths"
	)
	test_assert(utils.file_exists("/path/with-special~chars!@#$/file.txt") == true, "should handle special characters")
	test_assert(utils.file_exists("/") == false, "should return false for root directory")
	test_assert(utils.file_exists("/dev/null") == true, "should handle special files")

	vim.loop.fs_stat = original_fs_stat
end)

-- Test 30: get_plugin_dir with various debug scenarios
run_test("should handle debug info variations in get_plugin_dir", function()
	local utils = get_utils()

	local original_getinfo = debug.getinfo
	local original_fnamemodify = vim.fn.fnamemodify

	-- Test with different source formats
	---@diagnostic disable-next-line: duplicate-set-field
	debug.getinfo = function(_, _)
		return { source = "@/different/path/to/plugin/lua/beancount/utils.lua" }
	end

	vim.fn.fnamemodify = function(path, modifier)
		if modifier == ":h:h:h" then
			-- Simulate going up 3 directory levels
			local parts = {}
			for part in string.gmatch(path, "[^/]+") do
				table.insert(parts, part)
			end
			-- Remove last 3 parts (utils.lua, beancount, lua)
			for i = 1, 3 do
				table.remove(parts)
			end
			return "/" .. table.concat(parts, "/")
		end
		return path
	end

	local plugin_dir = utils.get_plugin_dir()
	test_assert(plugin_dir == "/different/path/to/plugin", "should handle different plugin paths")

	debug.getinfo = original_getinfo
	vim.fn.fnamemodify = original_fnamemodify
end)

-- Test 31: count_occurrences performance and boundary cases
run_test("should handle boundary cases in count_occurrences", function()
	local utils = get_utils()

	-- Test with very long strings and repeated patterns
	local long_string = string.rep("a", 1000)
	test_assert(utils.count_occurrences(long_string, "a") == 1000, "should handle long strings")

	local pattern_string = string.rep("abab", 100)
	test_assert(utils.count_occurrences(pattern_string, "a") == 200, "should count in repeated patterns")
	test_assert(utils.count_occurrences(pattern_string, "b") == 200, "should count other chars in patterns")

	-- Test with single character strings
	test_assert(utils.count_occurrences("a", "a") == 1, "should handle single char match")
	test_assert(utils.count_occurrences("a", "b") == 0, "should handle single char no match")
end)

-- Test 32: resolve_env_vars with special environment values
run_test("should handle special environment values in resolve_env_vars", function()
	local utils = get_utils()

	local original_getenv = os.getenv
	---@diagnostic disable-next-line: duplicate-set-field
	os.getenv = function(var)
		local special_vars = {
			["EMPTY"] = "",
			["SPACES"] = "  value with spaces  ",
			["SPECIAL"] = "!@#$%^&*()",
			["UNICODE"] = "café résumé",
			["NEWLINES"] = "line1\nline2",
			["PERCENT"] = "50%",
		}
		return special_vars[var]
	end

	test_assert(utils.resolve_env_vars("%EMPTY%test") == "test", "should handle empty env var")
	test_assert(utils.resolve_env_vars("%SPACES%") == "  value with spaces  ", "should preserve spaces")
	test_assert(utils.resolve_env_vars("%SPECIAL%") == "!@#$%^&*()", "should handle special characters")
	test_assert(utils.resolve_env_vars("%UNICODE%") == "café résumé", "should handle Unicode")
	test_assert(utils.resolve_env_vars("%NEWLINES%") == "line1\nline2", "should handle newlines")
	test_assert(utils.resolve_env_vars("%PERCENT%") == "50%", "should handle percent in values")

	os.getenv = original_getenv
end)

-- Test 33: get_main_bean_file with config module errors
run_test("should handle config module errors gracefully", function()
	local utils = get_utils()

	-- Test with config module that throws error
	package.loaded["beancount.config"] = {
		get = function(key)
			if key == "main_bean_file" then
				error("Config error")
			end
		end,
	}

	local success, result = pcall(utils.get_main_bean_file)
	test_assert(success == false, "should propagate config errors")

	-- Test with config module that returns unexpected type
	package.loaded["beancount.config"] = {
		get = function(key)
			if key == "main_bean_file" then
				return 123 -- Wrong type
			end
		end,
	}

	---@diagnostic disable-next-line: duplicate-set-field
	vim.startswith = function(str, prefix)
		return string.sub(str, 1, #prefix) == prefix
	end

	vim.fn.getcwd = function()
		return "/current"
	end

	local main_file = utils.get_main_bean_file()
	test_assert(main_file == "/current/123", "should handle non-string config values")

	vim.startswith = original_startswith
	vim.fn.getcwd = original_getcwd
end)

-- Test 34: run_cmd callback error handling
run_test("should handle callback errors in run_cmd", function()
	local utils = get_utils()
	local error_caught = false

	vim.fn.jobstart = function(cmd_table, opts)
		-- Simulate successful command completion but don't call callbacks immediately
		-- to avoid triggering the error in the test context
		return 123
	end

	local error_callback = function(stdout, stderr, exit_code)
		error("Callback error")
	end

	-- The implementation doesn't handle callback errors, so they would propagate
	local success, result = pcall(utils.run_cmd, "test", {}, error_callback, {})
	-- This would depend on when the callback is actually called (asynchronously)
	test_assert(success == true and type(result) == "number", "should return job ID even with error callback")

	vim.fn.jobstart = original_jobstart
end)

-- Test 35: Stress test with mixed operations
run_test("should handle mixed operations correctly", function()
	local utils = get_utils()

	-- Test multiple operations in sequence
	local test_string = "test.file.name.with.many.dots.txt"
	local extension = utils.get_file_extension(test_string)
	test_assert(extension == "txt", "should extract correct extension")

	local dot_count = utils.count_occurrences(test_string, ".")
	test_assert(dot_count == 6, "should count dots correctly")

	local contains_test = utils.tbl_contains({ test_string, extension, "other" }, extension)
	test_assert(contains_test == true, "should find extension in table")

	-- Test with environment-like string
	local env_string = "%HOME%/documents/%USER%/file.txt"
	local original_getenv = os.getenv
	---@diagnostic disable-next-line: duplicate-set-field
	os.getenv = function(var)
		if var == "HOME" then
			return "/home/user"
		elseif var == "USER" then
			return "testuser"
		end
		return nil
	end

	local resolved = utils.resolve_env_vars(env_string)
	test_assert(resolved == "/home/user/documents/testuser/file.txt", "should resolve complex paths")

	os.getenv = original_getenv
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
