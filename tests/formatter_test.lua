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

-- Exercise the TextChangedI callback in a real buffer so every accepted flag
-- gets the same indentation as '*', while directives and existing text stay intact.
local markers = { "*", "!", "&", "#", "?", "%", "txn" }
for byte = string.byte("A"), string.byte("Z") do
  table.insert(markers, string.char(byte))
end

local function check_new_line(header, current_line, expandtab, expected)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(bufnr)
  vim.bo.expandtab = expandtab
  vim.bo.shiftwidth = 2
  formatter.setup_buffer(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { header, current_line })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  vim.api.nvim_exec_autocmds("TextChangedI", { buffer = bufnr })
  local actual = vim.fn.getline(2)
  vim.api.nvim_buf_delete(bufnr, { force = true })
  test_assert(actual == expected, "expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(actual))
end

for _, marker in ipairs(markers) do
  run_test("new posting line indents after " .. marker, function()
    local header = '2026-09-09 ' .. marker .. ' "someone" "something"'
    check_new_line(header, "", true, "  ")
    check_new_line(header, "", false, "\t")
  end)
end

for _, header in ipairs({
  "2026-09-09 open Assets:Cash",
  '2026-09-09 note Assets:Cash "something"',
  '2026-09-09 TRUE "someone" "something"',
  '2026-09-09 txnInvalid "something"',
  '; 2026-09-09 T "something"',
  '  2026-09-09 T "something"',
}) do
  run_test("does not indent after " .. header, function()
    check_new_line(header, "", true, "")
  end)
end

run_test("preserves existing posting text and indentation", function()
  for _, line in ipairs({ "  ", "\t", "  Assets:Cash" }) do
    check_new_line('2026-09-09 T "someone" "something"', line, true, line)
  end
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
