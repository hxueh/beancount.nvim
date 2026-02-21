-- Comprehensive functional tests for beancount formatter
-- Tests indent_posting_line, balance line formatting, posting line formatting, and edge cases

-- Add lua path to find beancount modules
---@diagnostic disable-next-line: redundant-parameter
vim.opt.runtimepath:prepend(vim.fn.getcwd())

print("Running formatter tests...")

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
    print("  ✗ " .. name .. ": " .. tostring(err))
  end
end

-- Load the formatter module
local formatter = require("beancount.formatter")
local config = require("beancount.config")

-- Initialize config with defaults
config.setup({})

-- ============================================================================
-- Indentation Tests (from upstream)
-- ============================================================================

-- Verify indent_posting_line uses tab when expandtab=false
run_test("indent_posting_line uses tab when expandtab=false", function()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_buf_set_option(bufnr, "expandtab", false)
  vim.api.nvim_buf_set_option(bufnr, "shiftwidth", 4)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "" })
  formatter.indent_posting_line(1)
  local line = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1]
  local col = vim.fn.col(".")
  test_assert(line == "\t", "expected tab character, got: " .. vim.inspect(line))
  test_assert(col == #line, "expected cursor at end of indent, got: " .. tostring(col))
  vim.api.nvim_buf_delete(bufnr, { force = true })
end)

-- Verify indent_posting_line uses spaces when expandtab=true
run_test("indent_posting_line uses spaces when expandtab=true", function()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_buf_set_option(bufnr, "expandtab", true)
  vim.api.nvim_buf_set_option(bufnr, "shiftwidth", 4)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "" })
  formatter.indent_posting_line(1)
  local line = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1]
  local col = vim.fn.col(".")
  test_assert(line == "    ", "expected 4 spaces, got: " .. vim.inspect(line))
  test_assert(col == #line, "expected cursor at end of indent, got: " .. tostring(col))
  vim.api.nvim_buf_delete(bufnr, { force = true })
end)

-- Verify indent_posting_line uses spaces with shiftwidth=2 when expandtab=true
run_test("indent_posting_line uses 2 spaces when shiftwidth=2 and expandtab=true", function()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_buf_set_option(bufnr, "expandtab", true)
  vim.api.nvim_buf_set_option(bufnr, "shiftwidth", 2)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "" })
  formatter.indent_posting_line(1)
  local line = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1]
  local col = vim.fn.col(".")
  test_assert(line == "  ", "expected 2 spaces, got: " .. vim.inspect(line))
  test_assert(col == #line, "expected cursor at end of indent, got: " .. tostring(col))
  vim.api.nvim_buf_delete(bufnr, { force = true })
end)

-- ============================================================================
-- Balance Line Formatting Tests
-- ============================================================================

-- Test is_balance_line function
run_test("should identify balance directive lines", function()
  test_assert(formatter.is_balance_line("2024-01-01 balance Assets:Cash  100.00 USD"), "should match balance line")
  test_assert(formatter.is_balance_line("2024-12-31 balance Liabilities:CreditCard  -500.00 USD"), "should match negative balance")
  test_assert(not formatter.is_balance_line("  Assets:Cash  100.00 USD"), "should not match posting line")
  test_assert(not formatter.is_balance_line("2024-01-01 * \"Transaction\""), "should not match transaction header")
end)

-- Test format_balance_line with decimal point
run_test("should format balance line with decimal point", function()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(bufnr)

  -- Set a balance line with misaligned amount
  vim.fn.setline(1, "2024-01-01 balance Assets:Cash 100.00 USD")

  -- Format the line
  formatter.format_balance_line(1, 60)

  -- Check that the line is formatted correctly
  local result = vim.fn.getline(1)
  -- The decimal point should be at column 60 (separator_col)
  local decimal_pos = result:find("%.")
  test_assert(decimal_pos == 60, "decimal point should be at column 60, got " .. tostring(decimal_pos))

  vim.api.nvim_buf_delete(bufnr, { force = true })
end)

-- Test format_balance_line without decimal point
run_test("should format balance line without decimal point", function()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(bufnr)

  -- Set a balance line without decimal point
  vim.fn.setline(1, "2024-01-01 balance Assets:Cash 100 USD")

  -- Format the line
  formatter.format_balance_line(1, 60)

  -- Check that the line is formatted (simple alignment)
  local result = vim.fn.getline(1)
  test_assert(result:match("^2024%-01%-01 balance Assets:Cash%s+100 USD$"), "should align amount at separator column")

  vim.api.nvim_buf_delete(bufnr, { force = true })
end)

-- Test format_balance_line with CJK account names
run_test("should format balance line with CJK characters", function()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(bufnr)

  -- Set a balance line with CJK characters
  vim.fn.setline(1, "2024-01-01 balance Assets:现金 100.00 USD")

  -- Format the line with CJK width handling
  config.setup({ fixed_cjk_width = true })
  formatter.format_balance_line(1, 60)

  -- Check that the line is formatted
  local result = vim.fn.getline(1)
  test_assert(result:match("^2024%-01%-01 balance Assets:现金%s+%d+%.%d+ USD$"), "should format with CJK characters")

  -- Reset config
  config.setup({ fixed_cjk_width = false })
  vim.api.nvim_buf_delete(bufnr, { force = true })
end)

-- Test format_balance_line with tolerance specification
run_test("should format balance line with tolerance", function()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(bufnr)

  -- Set a balance line with tolerance
  vim.fn.setline(1, "2024-01-01 balance Assets:Cash 100.00 ~ 0.01 USD")

  -- Format the line
  formatter.format_balance_line(1, 60)

  -- Check that the line is formatted correctly
  local result = vim.fn.getline(1)
  local decimal_pos = result:find("%.")
  test_assert(decimal_pos == 60, "decimal point should be at column 60 with tolerance")

  vim.api.nvim_buf_delete(bufnr, { force = true })
end)

-- ============================================================================
-- Posting Line Formatting Tests
-- ============================================================================

-- Test is_posting_line function
run_test("should identify posting lines", function()
  test_assert(formatter.is_posting_line("    Assets:Cash  100.00 USD"), "should match posting line")
  test_assert(formatter.is_posting_line("  Expenses:Food  50.00 USD"), "should match posting with 2 spaces")
  test_assert(not formatter.is_posting_line("2024-01-01 balance Assets:Cash  100.00 USD"), "should not match balance line")
  test_assert(not formatter.is_posting_line("Assets:Cash  100.00 USD"), "should not match line without indent")
end)

-- Test format_posting_line
run_test("should format posting line with decimal point", function()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(bufnr)

  -- Set a posting line with misaligned amount
  vim.fn.setline(1, "    Assets:Cash 100.00 USD")

  -- Format the line
  formatter.format_posting_line(1, 60)

  -- Check that the line is formatted correctly
  local result = vim.fn.getline(1)
  local decimal_pos = result:find("%.")
  test_assert(decimal_pos == 60, "decimal point should be at column 60")

  vim.api.nvim_buf_delete(bufnr, { force = true })
end)

-- Test align_current_line for balance lines
run_test("should trigger alignment for balance lines on decimal insertion", function()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(bufnr)

  -- Set a balance line
  vim.fn.setline(1, "2024-01-01 balance Assets:Cash 100. USD")
  vim.fn.cursor(1, 40) -- Position cursor after decimal point

  -- Trigger alignment
  formatter.align_current_line()

  -- Check that the line is formatted
  local result = vim.fn.getline(1)
  test_assert(result:match("^2024%-01%-01 balance Assets:Cash%s+100%. USD$"), "should align balance line")

  vim.api.nvim_buf_delete(bufnr, { force = true })
end)

-- Test whitespace normalization documentation
run_test("should normalize whitespace in balance lines", function()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(bufnr)

  -- Set a balance line with multiple spaces
  vim.fn.setline(1, "2024-01-01  balance  Assets:Cash  100.00 USD")

  -- Format the line
  formatter.format_balance_line(1, 60)

  -- Check that whitespace is normalized to single spaces
  local result = vim.fn.getline(1)
  test_assert(result:match("^2024%-01%-01 balance Assets:Cash%s+100%.00 USD$"), "should normalize to single spaces")

  vim.api.nvim_buf_delete(bufnr, { force = true })
end)

-- Print test summary
print("\nTest Summary:")
print("Tests run: " .. tests_run)
print("Tests passed: " .. tests_passed)
print("Tests failed: " .. (tests_run - tests_passed))

if tests_passed == tests_run then
  print("\n✓ All tests passed!\n")
  os.exit(0)
else
  print("\n✗ Some tests failed!\n")
  os.exit(1)
end
