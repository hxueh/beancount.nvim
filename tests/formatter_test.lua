-- Tests for beancount formatter module
-- Verifies indent_posting_line respects user expandtab setting

---@diagnostic disable-next-line: redundant-parameter
vim.opt.runtimepath:prepend(vim.fn.getcwd())

print("Running formatter tests...")

local function test_assert(condition, message)
  if not condition then
    error("Test failed: " .. (message or "assertion failed"))
  end
end

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

local formatter = require("beancount.formatter")

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
