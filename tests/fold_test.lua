-- Comprehensive functional tests for beancount fold module
-- Tests all folding functionality without complex test framework

-- Add lua path to find beancount modules
vim.opt.runtimepath:prepend(vim.fn.getcwd())

print("Running comprehensive fold tests...")

local function test_assert(condition, message)
	if not condition then
		error("Test failed: " .. (message or "assertion failed"))
	end
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

-- Helper to get fold module
local function get_fold()
	package.loaded["beancount.fold"] = nil
	return require("beancount.fold")
end

-- Mock vim functions
local original_getline = vim.fn.getline
local original_v_lnum = vim.v.lnum

-- Mock vim.fn.getline and vim.v.lnum for testing
local function mock_fold_context(line_content, line_number)
	vim.fn.getline = function(lnum)
		return line_content
	end
	vim.v = vim.v or {}
	vim.v.lnum = line_number or 1
end

local function restore_vim_functions()
	vim.fn.getline = original_getline
	vim.v.lnum = original_v_lnum
end

-- Test 1: Basic module loading
run_test("should load fold module", function()
	local fold = get_fold()
	test_assert(type(fold) == "table", "fold should be a table")
	test_assert(type(fold.foldexpr) == "function", "fold.foldexpr should be a function")
end)

-- Test 2: Transaction lines with * flag
run_test("should start fold for transaction with * flag", function()
	local fold = get_fold()

	mock_fold_context('2024-01-15 * "Test transaction"', 1)
	local result = fold.foldexpr()
	test_assert(result == ">1", "should return '>1' for transaction with * flag")

	mock_fold_context('2025-12-31 * "Another transaction"', 2)
	local result2 = fold.foldexpr()
	test_assert(result2 == ">1", "should return '>1' for any date with * flag")

	restore_vim_functions()
end)

-- Test 3: Transaction lines with ! flag
run_test("should start fold for transaction with ! flag", function()
	local fold = get_fold()

	mock_fold_context('2024-03-20 ! "Cleared transaction"', 1)
	local result = fold.foldexpr()
	test_assert(result == ">1", "should return '>1' for transaction with ! flag")

	restore_vim_functions()
end)

-- Test 4: Open directive
run_test("should start fold for open directive", function()
	local fold = get_fold()

	mock_fold_context("2024-01-01 open Assets:Checking:Bank1", 1)
	local result = fold.foldexpr()
	test_assert(result == ">1", "should return '>1' for open directive")

	restore_vim_functions()
end)

-- Test 5: Close directive
run_test("should start fold for close directive", function()
	local fold = get_fold()

	mock_fold_context("2024-12-31 close Assets:Checking:Old", 1)
	local result = fold.foldexpr()
	test_assert(result == ">1", "should return '>1' for close directive")

	restore_vim_functions()
end)

-- Test 6: Balance directive
run_test("should start fold for balance directive", function()
	local fold = get_fold()

	mock_fold_context("2024-06-30 balance Assets:Checking 1500.00 USD", 1)
	local result = fold.foldexpr()
	test_assert(result == ">1", "should return '>1' for balance directive")

	restore_vim_functions()
end)

-- Test 7: Pad directive
run_test("should start fold for pad directive", function()
	local fold = get_fold()

	mock_fold_context("2024-01-01 pad Assets:Checking Equity:Opening-Balances", 1)
	local result = fold.foldexpr()
	test_assert(result == ">1", "should return '>1' for pad directive")

	restore_vim_functions()
end)

-- Test 8: Plugin directive
run_test("should start fold for plugin directive", function()
	local fold = get_fold()

	mock_fold_context('plugin "beancount.plugins.auto_accounts"', 1)
	local result = fold.foldexpr()
	test_assert(result == ">1", "should return '>1' for plugin directive")

	restore_vim_functions()
end)

-- Test 9: Option directive
run_test("should start fold for option directive", function()
	local fold = get_fold()

	mock_fold_context('option "title" "My Accounting"', 1)
	local result = fold.foldexpr()
	test_assert(result == ">1", "should return '>1' for option directive")

	restore_vim_functions()
end)

-- Test 10: Empty lines close fold
run_test("should close fold for empty lines", function()
	local fold = get_fold()

	mock_fold_context("", 1)
	local result = fold.foldexpr()
	test_assert(result == "0", "should return '0' for empty line")

	mock_fold_context("   ", 2)
	local result2 = fold.foldexpr()
	test_assert(result2 == "0", "should return '0' for line with only spaces")

	mock_fold_context("\t\t", 3)
	local result3 = fold.foldexpr()
	test_assert(result3 == "0", "should return '0' for line with only tabs")

	restore_vim_functions()
end)

-- Test 11: Posting lines continue fold
run_test("should continue fold for posting lines", function()
	local fold = get_fold()

	mock_fold_context("  Assets:Checking  100.00 USD", 1)
	local result = fold.foldexpr()
	test_assert(result == "=", "should return '=' for posting line with spaces")

	mock_fold_context("\tExpenses:Groceries  50.00 USD", 2)
	local result2 = fold.foldexpr()
	test_assert(result2 == "=", "should return '=' for posting line with tab")

	restore_vim_functions()
end)

-- Test 12: Metadata lines continue fold
run_test("should continue fold for metadata lines", function()
	local fold = get_fold()

	mock_fold_context('  key: "value"', 1)
	local result = fold.foldexpr()
	test_assert(result == "=", "should return '=' for metadata line")

	mock_fold_context('    nested-key: "nested-value"', 2)
	local result2 = fold.foldexpr()
	test_assert(result2 == "=", "should return '=' for deeply indented metadata")

	restore_vim_functions()
end)

-- Test 13: Regular lines maintain fold level
run_test("should maintain fold level for regular lines", function()
	local fold = get_fold()

	mock_fold_context("regular line without special meaning", 1)
	local result = fold.foldexpr()
	test_assert(result == "=", "should return '=' for regular line")

	mock_fold_context("just some text", 2)
	local result2 = fold.foldexpr()
	test_assert(result2 == "=", "should return '=' for text line")

	restore_vim_functions()
end)

-- Test 14: Date format variations for transactions
run_test("should handle date format variations in transactions", function()
	local fold = get_fold()

	-- Valid date formats
	mock_fold_context('2024-01-01 * "Valid transaction"', 1)
	local result1 = fold.foldexpr()
	test_assert(result1 == ">1", "should handle standard date format")

	mock_fold_context('2024-12-31 ! "End of year"', 2)
	local result2 = fold.foldexpr()
	test_assert(result2 == ">1", "should handle year-end date")

	-- Invalid date formats should not match
	mock_fold_context('24-01-01 * "Invalid year"', 3)
	local result3 = fold.foldexpr()
	test_assert(result3 == "=", "should not match 2-digit year")

	mock_fold_context('2024-1-1 * "Invalid month/day"', 4)
	local result4 = fold.foldexpr()
	test_assert(result4 == "=", "should not match single-digit month/day")

	restore_vim_functions()
end)

-- Test 15: Directive format variations
run_test("should handle directive format variations", function()
	local fold = get_fold()

	-- Valid directive formats
	mock_fold_context("2024-01-01 open Assets:Bank", 1)
	local result1 = fold.foldexpr()
	test_assert(result1 == ">1", "should match basic open directive")

	mock_fold_context("2024-01-01 close Assets:Old-Bank", 2)
	local result2 = fold.foldexpr()
	test_assert(result2 == ">1", "should match close directive with hyphen")

	mock_fold_context("2024-06-30 balance Assets:Checking:Main 1000.00 USD", 3)
	local result3 = fold.foldexpr()
	test_assert(result3 == ">1", "should match balance directive with amount")

	-- Invalid formats should not match
	mock_fold_context("open Assets:Bank", 4)
	local result4 = fold.foldexpr()
	test_assert(result4 == "=", "should not match directive without date")

	mock_fold_context("2024-01-01open Assets:Bank", 5)
	local result5 = fold.foldexpr()
	test_assert(result5 == "=", "should not match directive without space")

	restore_vim_functions()
end)

-- Test 16: Plugin directive variations
run_test("should handle plugin directive variations", function()
	local fold = get_fold()

	mock_fold_context('plugin "beancount.plugins.auto_accounts"', 1)
	local result1 = fold.foldexpr()
	test_assert(result1 == ">1", "should match plugin with quotes")

	mock_fold_context("plugin 'beancount.plugins.forecasting'", 2)
	local result2 = fold.foldexpr()
	test_assert(result2 == ">1", "should match plugin with single quotes")

	mock_fold_context("plugin beancount.plugins.simple", 3)
	local result3 = fold.foldexpr()
	test_assert(result3 == ">1", "should match plugin without quotes")

	restore_vim_functions()
end)

-- Test 17: Option directive variations
run_test("should handle option directive variations", function()
	local fold = get_fold()

	mock_fold_context('option "title" "My Ledger"', 1)
	local result1 = fold.foldexpr()
	test_assert(result1 == ">1", "should match option with double quotes")

	mock_fold_context("option 'operating_currency' 'USD'", 2)
	local result2 = fold.foldexpr()
	test_assert(result2 == ">1", "should match option with single quotes")

	mock_fold_context("option account_previous_balances True", 3)
	local result3 = fold.foldexpr()
	test_assert(result3 == ">1", "should match option without quotes")

	restore_vim_functions()
end)

-- Test 18: Complex transaction structures
run_test("should handle complex transaction structures", function()
	local fold = get_fold()

	-- Transaction line should start fold
	mock_fold_context('2024-03-15 * "Grocery shopping" ^link #tag', 1)
	local result1 = fold.foldexpr()
	test_assert(result1 == ">1", "should start fold for transaction with links and tags")

	-- Posting lines should continue fold
	mock_fold_context("  Assets:Checking  -85.42 USD", 2)
	local result2 = fold.foldexpr()
	test_assert(result2 == "=", "should continue fold for first posting")

	mock_fold_context("  Expenses:Food:Groceries", 3)
	local result3 = fold.foldexpr()
	test_assert(result3 == "=", "should continue fold for second posting")

	-- Metadata should continue fold
	mock_fold_context('    receipt: "receipt-123.pdf"', 4)
	local result4 = fold.foldexpr()
	test_assert(result4 == "=", "should continue fold for metadata")

	-- Empty line should close fold
	mock_fold_context("", 5)
	local result5 = fold.foldexpr()
	test_assert(result5 == "0", "should close fold with empty line")

	restore_vim_functions()
end)

-- Test 19: Mixed whitespace handling
run_test("should handle mixed whitespace correctly", function()
	local fold = get_fold()

	-- Lines with only different types of whitespace
	mock_fold_context("   \t   ", 1)
	local result1 = fold.foldexpr()
	test_assert(result1 == "0", "should close fold for mixed whitespace")

	mock_fold_context("\t", 2)
	local result2 = fold.foldexpr()
	test_assert(result2 == "0", "should close fold for single tab")

	-- Indented content
	mock_fold_context("  \tAssets:Checking  100.00 USD", 3)
	local result3 = fold.foldexpr()
	test_assert(result3 == "=", "should continue fold for mixed indentation")

	restore_vim_functions()
end)

-- Test 20: Edge cases and boundary conditions
run_test("should handle edge cases correctly", function()
	local fold = get_fold()

	-- Almost valid date formats - Note: pattern matching doesn't validate actual date values
	mock_fold_context('2024-13-01 * "Invalid month"', 1)
	local result1 = fold.foldexpr()
	test_assert(result1 == ">1", "pattern matches format but doesn't validate actual date values")

	mock_fold_context('2024-01-32 * "Invalid day"', 2)
	local result2 = fold.foldexpr()
	test_assert(result2 == ">1", "pattern matches format but doesn't validate actual date values")

	-- Transaction flags in wrong position
	mock_fold_context('* 2024-01-01 "Wrong flag position"', 3)
	local result3 = fold.foldexpr()
	test_assert(result3 == "=", "should not match flag before date")

	-- Directives with extra spaces
	mock_fold_context("2024-01-01  open  Assets:Bank", 4)
	local result4 = fold.foldexpr()
	test_assert(result4 == ">1", "should match directive with extra spaces")

	restore_vim_functions()
end)

-- Test 21: Comment lines
run_test("should handle comment lines correctly", function()
	local fold = get_fold()

	-- Comments should maintain current fold level
	mock_fold_context("; This is a comment", 1)
	local result1 = fold.foldexpr()
	test_assert(result1 == "=", "should maintain fold level for comment")

	mock_fold_context("  ; Indented comment", 2)
	local result2 = fold.foldexpr()
	test_assert(result2 == "=", "should continue fold for indented comment")

	restore_vim_functions()
end)

-- Test 22: Special characters in content
run_test("should handle special characters in content", function()
	local fold = get_fold()

	-- Transaction with special characters
	mock_fold_context('2024-01-01 * "Café & Restaurant (50% tip)"', 1)
	local result1 = fold.foldexpr()
	test_assert(result1 == ">1", "should handle special characters in description")

	-- Posting with special characters
	mock_fold_context("  Expenses:Dining:Café&Restaurant  25.50 USD", 2)
	local result2 = fold.foldexpr()
	test_assert(result2 == "=", "should handle special characters in account names")

	restore_vim_functions()
end)

-- Test 23: Year boundary dates
run_test("should handle year boundary dates correctly", function()
	local fold = get_fold()

	mock_fold_context('1970-01-01 * "Unix epoch"', 1)
	local result1 = fold.foldexpr()
	test_assert(result1 == ">1", "should handle early dates")

	mock_fold_context('2099-12-31 * "Future date"', 2)
	local result2 = fold.foldexpr()
	test_assert(result2 == ">1", "should handle future dates")

	restore_vim_functions()
end)

-- Test 24: Directive case sensitivity
run_test("should handle directive case sensitivity", function()
	local fold = get_fold()

	-- Lowercase directives (standard)
	mock_fold_context("2024-01-01 open Assets:Bank", 1)
	local result1 = fold.foldexpr()
	test_assert(result1 == ">1", "should match lowercase open")

	-- Uppercase directives should not match (case sensitive)
	mock_fold_context("2024-01-01 OPEN Assets:Bank", 2)
	local result2 = fold.foldexpr()
	test_assert(result2 == "=", "should not match uppercase OPEN")

	mock_fold_context("2024-01-01 Open Assets:Bank", 3)
	local result3 = fold.foldexpr()
	test_assert(result3 == "=", "should not match capitalized Open")

	restore_vim_functions()
end)

-- Test 25: Performance test with long lines
run_test("should handle long lines efficiently", function()
	local fold = get_fold()

	-- Very long transaction description
	local long_desc = string.rep("very long description ", 100)
	mock_fold_context('2024-01-01 * "' .. long_desc .. '"', 1)
	local result1 = fold.foldexpr()
	test_assert(result1 == ">1", "should handle very long transaction descriptions")

	-- Very long account name
	local long_account = "Assets:Bank:" .. string.rep("VeryLongAccountName", 50)
	mock_fold_context("  " .. long_account .. "  100.00 USD", 2)
	local result2 = fold.foldexpr()
	test_assert(result2 == "=", "should handle very long account names")

	restore_vim_functions()
end)

-- Test 26: Multiple consecutive patterns
run_test("should handle multiple consecutive patterns", function()
	local fold = get_fold()

	-- Multiple transactions in sequence
	mock_fold_context('2024-01-01 * "Transaction 1"', 1)
	local result1 = fold.foldexpr()
	test_assert(result1 == ">1", "should start fold for first transaction")

	mock_fold_context('2024-01-02 * "Transaction 2"', 2)
	local result2 = fold.foldexpr()
	test_assert(result2 == ">1", "should start new fold for second transaction")

	-- Multiple directives in sequence
	mock_fold_context("2024-01-01 open Assets:Bank1", 3)
	local result3 = fold.foldexpr()
	test_assert(result3 == ">1", "should start fold for first directive")

	mock_fold_context("2024-01-01 open Assets:Bank2", 4)
	local result4 = fold.foldexpr()
	test_assert(result4 == ">1", "should start fold for second directive")

	restore_vim_functions()
end)

-- Test 27: Context preservation across calls
run_test("should preserve context correctly across function calls", function()
	local fold = get_fold()

	-- Test that function doesn't maintain internal state
	mock_fold_context('2024-01-01 * "Transaction"', 1)
	local result1 = fold.foldexpr()
	test_assert(result1 == ">1", "first call should return >1")

	-- Different line should not be affected by previous call
	mock_fold_context("  Assets:Checking  100.00 USD", 2)
	local result2 = fold.foldexpr()
	test_assert(result2 == "=", "second call should return = independent of first")

	-- Back to transaction line
	mock_fold_context('2024-01-02 * "Another transaction"', 3)
	local result3 = fold.foldexpr()
	test_assert(result3 == ">1", "third call should return >1 independent of previous")

	restore_vim_functions()
end)

-- Test 28: Transaction flag variations
run_test("should handle all valid transaction flags", function()
	local fold = get_fold()

	-- Standard flags
	mock_fold_context('2024-01-01 * "Cleared transaction"', 1)
	local result1 = fold.foldexpr()
	test_assert(result1 == ">1", "should handle * flag")

	mock_fold_context('2024-01-01 ! "Pending transaction"', 2)
	local result2 = fold.foldexpr()
	test_assert(result2 == ">1", "should handle ! flag")

	-- Invalid flags should not match
	mock_fold_context('2024-01-01 ? "Invalid flag"', 3)
	local result3 = fold.foldexpr()
	test_assert(result3 == "=", "should not match invalid flag ?")

	mock_fold_context('2024-01-01 # "Invalid flag"', 4)
	local result4 = fold.foldexpr()
	test_assert(result4 == "=", "should not match invalid flag #")

	restore_vim_functions()
end)

-- Test 29: Stress test with various patterns
run_test("should handle stress test with mixed patterns", function()
	local fold = get_fold()

	local test_lines = {
		{ '2024-01-01 * "Transaction"', ">1" },
		{ "  Assets:Checking  100.00 USD", "=" },
		{ "  Expenses:Food", "=" },
		{ "", "0" },
		{ "2024-01-02 open Assets:Savings", ">1" },
		{ "", "0" },
		{ 'plugin "auto_accounts"', ">1" },
		{ "", "0" },
		{ 'option "title" "My Ledger"', ">1" },
		{ "", "0" },
		{ "2024-01-03 balance Assets:Checking 1000.00 USD", ">1" },
		{ "", "0" },
		{ "2024-01-04 pad Assets:Checking Equity:Opening", ">1" },
		{ "", "0" },
		{ "2024-01-05 close Assets:Old", ">1" },
		{ "", "0" },
		{ '2024-01-06 ! "Pending"', ">1" },
		{ "  Assets:Checking", "=" },
		{ '    metadata: "value"', "=" },
		{ "  Expenses:Unknown", "=" },
		{ "", "0" },
	}

	for i, line_data in ipairs(test_lines) do
		local line_content, expected = line_data[1], line_data[2]
		mock_fold_context(line_content, i)
		local result = fold.foldexpr()
		test_assert(
			result == expected,
			"line " .. i .. " ('" .. line_content .. "') should return '" .. expected .. "' but got '" .. result .. "'"
		)
	end

	restore_vim_functions()
end)

-- Test 30: Invalid patterns that should not match
run_test("should not match invalid patterns", function()
	local fold = get_fold()

	local invalid_patterns = {
		'2024-1-1 * "Bad date format"',
		'24-01-01 * "Short year"',
		'2024/01/01 * "Wrong separator"',
		'2024-01-01* "No space before flag"',
		'2024-01-01 & "Invalid flag"',
		"2024-01-01 opne Assets:Bank", -- typo
		"2024-01-01  oopen Assets:Bank", -- double o
		'PLUGIN "test"', -- wrong case
		'OPTION "test" "value"', -- wrong case
	}

	for i, pattern in ipairs(invalid_patterns) do
		mock_fold_context(pattern, i)
		local result = fold.foldexpr()
		test_assert(result == "=", "invalid pattern '" .. pattern .. "' should not match (should return '=')")
	end

	restore_vim_functions()
end)

-- Test 31: Pattern behavior edge cases
run_test("should handle pattern behavior edge cases", function()
	local fold = get_fold()

	-- These patterns actually DO match due to how the regex works
	mock_fold_context('2024-01-01 *"No space after flag"', 1)
	local result1 = fold.foldexpr()
	test_assert(result1 == ">1", "pattern [*!] matches flag without requiring space after")

	mock_fold_context("2024-01-01 !description", 2)
	local result2 = fold.foldexpr()
	test_assert(result2 == ">1", "pattern [*!] matches ! flag followed by any character")

	-- plugin and option by themselves do match the patterns
	mock_fold_context("plugin", 3)
	local result3 = fold.foldexpr()
	test_assert(result3 == ">1", "bare plugin matches ^plugin pattern")

	mock_fold_context("option", 4)
	local result4 = fold.foldexpr()
	test_assert(result4 == ">1", "bare option matches ^option pattern")

	restore_vim_functions()
end)

-- Test 32: Advanced Beancount directives edge cases
run_test("should handle advanced directive edge cases", function()
	local fold = get_fold()

	-- Document directive
	mock_fold_context('2024-01-01 document Assets:Bank "/path/to/statement.pdf"', 1)
	local result1 = fold.foldexpr()
	test_assert(result1 == "=", "document directive should not start fold (not in current patterns)")

	-- Note directive
	mock_fold_context('2024-01-01 note Assets:Bank "Account opened"', 2)
	local result2 = fold.foldexpr()
	test_assert(result2 == "=", "note directive should not start fold (not in current patterns)")

	-- Event directive
	mock_fold_context('2024-01-01 event "location" "New York"', 3)
	local result3 = fold.foldexpr()
	test_assert(result3 == "=", "event directive should not start fold (not in current patterns)")

	-- Query directive
	mock_fold_context('2024-01-01 query "cash" "SELECT account WHERE account ~ \'Cash\'"', 4)
	local result4 = fold.foldexpr()
	test_assert(result4 == "=", "query directive should not start fold (not in current patterns)")

	-- Custom directive
	mock_fold_context('2024-01-01 custom "budget" Assets:Checking 1000.00 USD', 5)
	local result5 = fold.foldexpr()
	test_assert(result5 == "=", "custom directive should not start fold (not in current patterns)")

	restore_vim_functions()
end)

-- Test 33: Whitespace and indentation edge cases
run_test("should handle complex whitespace scenarios", function()
	local fold = get_fold()

	-- Transaction with leading whitespace (should not match)
	mock_fold_context('  2024-01-01 * "Indented transaction"', 1)
	local result1 = fold.foldexpr()
	test_assert(result1 == "=", "indented transaction should continue fold, not start new one")

	-- Mixed tabs and spaces in posting
	mock_fold_context("\t  Assets:Checking  100.00 USD", 2)
	local result2 = fold.foldexpr()
	test_assert(result2 == "=", "mixed tabs and spaces should continue fold")

	-- Very deeply indented metadata
	mock_fold_context('                    deep-key: "deep-value"', 3)
	local result3 = fold.foldexpr()
	test_assert(result3 == "=", "very deep indentation should continue fold")

	-- Line with only a single space
	mock_fold_context(" ", 4)
	local result4 = fold.foldexpr()
	test_assert(result4 == "0", "single space should close fold")

	-- Line with Unicode whitespace characters
	mock_fold_context("\u{00A0}\u{2000}", 5) -- non-breaking space + en quad
	local result5 = fold.foldexpr()
	test_assert(result5 == "=", "Unicode whitespace should maintain fold level")

	restore_vim_functions()
end)

-- Test 34: Transaction flag edge cases
run_test("should handle transaction flag edge cases", function()
	local fold = get_fold()

	-- Multiple flags (invalid but pattern might match first one)
	mock_fold_context('2024-01-01 *! "Multiple flags"', 1)
	local result1 = fold.foldexpr()
	test_assert(result1 == ">1", "should match first valid flag")

	-- Flag with extra spaces
	mock_fold_context('2024-01-01   *   "Extra spaces"', 2)
	local result2 = fold.foldexpr()
	test_assert(result2 == ">1", "should handle extra spaces around flag")

	-- Tab before flag
	mock_fold_context('2024-01-01\t*\t"Tab separator"', 3)
	local result3 = fold.foldexpr()
	test_assert(result3 == ">1", "should handle tab before flag")

	-- Flag at end of line
	mock_fold_context("2024-01-01 *", 4)
	local result4 = fold.foldexpr()
	test_assert(result4 == ">1", "should handle flag at end of line")

	restore_vim_functions()
end)

-- Test 35: Directive spacing variations
run_test("should handle directive spacing variations", function()
	local fold = get_fold()

	-- Multiple spaces between date and directive
	mock_fold_context("2024-01-01    open    Assets:Bank", 1)
	local result1 = fold.foldexpr()
	test_assert(result1 == ">1", "should handle multiple spaces before directive")

	-- Tab between date and directive
	mock_fold_context("2024-01-01\topen\tAssets:Bank", 2)
	local result2 = fold.foldexpr()
	test_assert(result2 == ">1", "should handle tab before directive")

	-- Mixed whitespace
	mock_fold_context("2024-01-01 \t open Assets:Bank", 3)
	local result3 = fold.foldexpr()
	test_assert(result3 == ">1", "should handle mixed whitespace")

	restore_vim_functions()
end)

-- Test 36: Plugin and option directive edge cases
run_test("should handle plugin/option directive edge cases", function()
	local fold = get_fold()

	-- Plugin with leading whitespace (should not match)
	mock_fold_context('  plugin "test.plugin"', 1)
	local result1 = fold.foldexpr()
	test_assert(result1 == "=", "indented plugin should continue fold")

	-- Option with leading whitespace
	mock_fold_context('\toption "title" "test"', 2)
	local result2 = fold.foldexpr()
	test_assert(result2 == "=", "indented option should continue fold")

	-- Plugin as part of larger word
	mock_fold_context('myplugin "test"', 3)
	local result3 = fold.foldexpr()
	test_assert(result3 == "=", "plugin as substring should not match")

	-- Option as part of larger word
	mock_fold_context('myoption "test"', 4)
	local result4 = fold.foldexpr()
	test_assert(result4 == "=", "option as substring should not match")

	restore_vim_functions()
end)

-- Test 37: Date boundary and format stress test
run_test("should handle date format stress test", function()
	local fold = get_fold()

	-- Leap year
	mock_fold_context('2024-02-29 * "Leap year"', 1)
	local result1 = fold.foldexpr()
	test_assert(result1 == ">1", "should handle leap year date")

	-- Year 2000
	mock_fold_context('2000-01-01 * "Y2K"', 2)
	local result2 = fold.foldexpr()
	test_assert(result2 == ">1", "should handle Y2K date")

	-- Far future
	mock_fold_context('2999-12-31 * "Far future"', 3)
	local result3 = fold.foldexpr()
	test_assert(result3 == ">1", "should handle far future date")

	-- Almost valid formats that should NOT match
	mock_fold_context('224-01-01 * "3-digit year"', 4)
	local result4 = fold.foldexpr()
	test_assert(result4 == "=", "should not match 3-digit year")

	mock_fold_context('20244-01-01 * "5-digit year"', 5)
	local result5 = fold.foldexpr()
	test_assert(result5 == "=", "should not match 5-digit year")

	restore_vim_functions()
end)

-- Test 38: Complex line content with special characters
run_test("should handle complex line content", function()
	local fold = get_fold()

	-- Transaction with Unicode in description
	mock_fold_context('2024-01-01 * "Café & Résumé 中文"', 1)
	local result1 = fold.foldexpr()
	test_assert(result1 == ">1", "should handle Unicode in transaction")

	-- Posting with currency symbols
	mock_fold_context("  Assets:Checking  €100.00", 2)
	local result2 = fold.foldexpr()
	test_assert(result2 == "=", "should handle currency symbols in posting")

	-- Account with special characters
	mock_fold_context("  Expenses:Dining:Café&Bar  $25.50", 3)
	local result3 = fold.foldexpr()
	test_assert(result3 == "=", "should handle special chars in account names")

	-- Metadata with complex values
	mock_fold_context('    receipt-url: "https://example.com/receipt?id=123&type=pdf"', 4)
	local result4 = fold.foldexpr()
	test_assert(result4 == "=", "should handle complex metadata values")

	restore_vim_functions()
end)

-- Test 39: Performance edge cases
run_test("should handle performance edge cases", function()
	local fold = get_fold()

	-- Extremely long line with valid transaction
	local long_description = string.rep("Very long transaction description ", 200)
	mock_fold_context('2024-01-01 * "' .. long_description .. '"', 1)
	local result1 = fold.foldexpr()
	test_assert(result1 == ">1", "should handle extremely long transaction lines")

	-- Very long account name
	local long_account_parts = {}
	for i = 1, 50 do
		table.insert(long_account_parts, "Level" .. i)
	end
	local long_account = table.concat(long_account_parts, ":")
	mock_fold_context("  " .. long_account .. "  100.00 USD", 2)
	local result2 = fold.foldexpr()
	test_assert(result2 == "=", "should handle very long account names")

	-- Line with many repeated patterns in description
	local repeated_content = string.rep("repeat ", 100)
	local repeated_pattern = '2024-01-01 * "' .. repeated_content .. '"'
	mock_fold_context(repeated_pattern, 3)
	local result3 = fold.foldexpr()
	test_assert(result3 == ">1", "should handle repeated patterns in description")

	restore_vim_functions()
end)

-- Test 40: Regex pattern boundary testing
run_test("should handle regex pattern boundaries", function()
	local fold = get_fold()

	-- Patterns that might cause regex issues
	mock_fold_context('2024-01-01 * "Pattern with [brackets] and (parens)"', 1)
	local result1 = fold.foldexpr()
	test_assert(result1 == ">1", "should handle brackets and parentheses")

	-- Patterns with backslashes
	mock_fold_context('2024-01-01 * "Path with\\backslashes\\here"', 2)
	local result2 = fold.foldexpr()
	test_assert(result2 == ">1", "should handle backslashes")

	-- Patterns with regex metacharacters
	mock_fold_context('2024-01-01 * "Regex meta: ^$.*+?{}[]()"', 3)
	local result3 = fold.foldexpr()
	test_assert(result3 == ">1", "should handle regex metacharacters")

	-- Empty description
	mock_fold_context('2024-01-01 * ""', 4)
	local result4 = fold.foldexpr()
	test_assert(result4 == ">1", "should handle empty description")

	restore_vim_functions()
end)

-- Test 41: Multi-byte character handling
run_test("should handle multi-byte characters correctly", function()
	local fold = get_fold()

	-- Asian characters in various positions
	mock_fold_context('2024-01-01 * "购买食品"', 1)
	local result1 = fold.foldexpr()
	test_assert(result1 == ">1", "should handle Chinese characters")

	mock_fold_context("  Assets:银行账户  100.00 CNY", 2)
	local result2 = fold.foldexpr()
	test_assert(result2 == "=", "should handle Chinese in account names")

	-- Emoji in content
	mock_fold_context('2024-01-01 * "Coffee ☕ and food 🍕"', 3)
	local result3 = fold.foldexpr()
	test_assert(result3 == ">1", "should handle emoji characters")

	-- Mixed scripts
	mock_fold_context("  Expenses:Dining:カフェ-Café  €15.50", 4)
	local result4 = fold.foldexpr()
	test_assert(result4 == "=", "should handle mixed scripts")

	restore_vim_functions()
end)

-- Test 42: Comment and string handling edge cases
run_test("should handle comment and string edge cases", function()
	local fold = get_fold()

	-- Comment that looks like transaction
	mock_fold_context('; 2024-01-01 * "This is a comment"', 1)
	local result1 = fold.foldexpr()
	test_assert(result1 == "=", "commented transaction should not start fold")

	-- Transaction with semicolon in description
	mock_fold_context('2024-01-01 * "Description; with semicolon"', 2)
	local result2 = fold.foldexpr()
	test_assert(result2 == ">1", "semicolon in description should not affect matching")

	-- String with escaped quotes
	mock_fold_context('2024-01-01 * "Description with \\"quoted\\" text"', 3)
	local result3 = fold.foldexpr()
	test_assert(result3 == ">1", "escaped quotes should not affect matching")

	-- Line ending with different comment styles
	mock_fold_context("  Assets:Checking  100.00 USD ; inline comment", 4)
	local result4 = fold.foldexpr()
	test_assert(result4 == "=", "posting with comment should continue fold")

	restore_vim_functions()
end)

-- Test 43: Malformed but partially matching patterns
run_test("should handle malformed but partially matching patterns", function()
	local fold = get_fold()

	-- Date-like strings in wrong positions
	mock_fold_context('Transaction on 2024-01-01 * "Wrong position"', 1)
	local result1 = fold.foldexpr()
	test_assert(result1 == "=", "date not at start should not match")

	-- Directive-like words in descriptions
	mock_fold_context('2024-01-01 * "Need to open account"', 2)
	local result2 = fold.foldexpr()
	test_assert(result2 == ">1", "directive words in description should not interfere")

	-- Numbers that look like dates
	mock_fold_context('20240101 * "No dashes"', 3)
	local result3 = fold.foldexpr()
	test_assert(result3 == "=", "date without dashes should not match")

	-- Almost correct directive format (typo: 'opens' instead of 'open')
	mock_fold_context("2024-01-01  opens Assets:Bank", 4)
	local result4 = fold.foldexpr()
	test_assert(result4 == "=", "typo in directive (opens instead of open) should not match")

	restore_vim_functions()
end)

-- Test 44: Nested structure simulation
run_test("should handle nested structure simulation", function()
	local fold = get_fold()

	-- Simulate a complete beancount file section
	local file_section = {
		{ 'plugin "beancount.plugins.auto_accounts"', ">1" },
		{ "", "0" },
		{ 'option "title" "My Ledger"', ">1" },
		{ 'option "operating_currency" "USD"', ">1" },
		{ "", "0" },
		{ "2024-01-01 open Assets:Checking", ">1" },
		{ "", "0" },
		{ '2024-01-01 * "Opening balance"', ">1" },
		{ "  Assets:Checking  1000.00 USD", "=" },
		{ "  Equity:Opening-Balances", "=" },
		{ "", "0" },
		{ '2024-01-15 * "Grocery shopping"', ">1" },
		{ "  Assets:Checking  -85.42 USD", "=" },
		{ "  Expenses:Food:Groceries", "=" },
		{ '    receipt: "receipt-001.pdf"', "=" },
		{ '    store: "Whole Foods"', "=" },
		{ "", "0" },
		{ "2024-01-31 balance Assets:Checking 914.58 USD", ">1" },
		{ "", "0" },
	}

	for i, line_data in ipairs(file_section) do
		local line_content, expected = line_data[1], line_data[2]
		mock_fold_context(line_content, i)
		local result = fold.foldexpr()
		test_assert(
			result == expected,
			"line " .. i .. " ('" .. line_content .. "') should return '" .. expected .. "' but got '" .. result .. "'"
		)
	end

	restore_vim_functions()
end)

-- Test 45: Memory and state isolation
run_test("should maintain proper state isolation", function()
	local fold = get_fold()

	-- Test that previous calls don't affect current ones
	local test_sequence = {
		'2024-01-01 * "First transaction"',
		"  Assets:Checking  100.00 USD",
		"",
		'plugin "test.plugin"',
		'2024-01-02 * "Second transaction"',
		"  Assets:Checking  -50.00 USD",
		'    metadata: "value"',
		"",
		"2024-01-03 open Assets:Savings",
		"",
	}

	local expected_results = { ">1", "=", "0", ">1", ">1", "=", "=", "0", ">1", "0" }

	for i, line_content in ipairs(test_sequence) do
		mock_fold_context(line_content, i)
		local result = fold.foldexpr()
		local expected = expected_results[i]
		test_assert(
			result == expected,
			"sequence "
				.. i
				.. " ('"
				.. line_content
				.. "') should return '"
				.. expected
				.. "' but got '"
				.. result
				.. "'"
		)
	end

	-- Test calling same line multiple times gives same result
	mock_fold_context('2024-01-01 * "Consistent"', 1)
	local result1 = fold.foldexpr()
	local result2 = fold.foldexpr()
	local result3 = fold.foldexpr()
	test_assert(result1 == result2 and result2 == result3, "multiple calls should return consistent results")

	restore_vim_functions()
end)

-- Print summary
print("\nTest Summary:")
print("Tests run: " .. tests_run)
print("Tests passed: " .. tests_passed)
print("Tests failed: " .. (tests_run - tests_passed))

if tests_passed == tests_run then
	print("\n✓ All tests passed!")
	vim.cmd("quit")
else
	print("\n✗ Some tests failed!")
	vim.cmd("cquit 1")
end
