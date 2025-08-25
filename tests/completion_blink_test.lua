-- Test for beancount.completion.blink module
-- Run with: nvim --headless --noplugin --clean -c "luafile tests/completion_blink_test.lua"

print("Testing beancount.completion.blink module")

-- Mock vim API functions
vim.api = vim.api or {}
vim.api.nvim_win_get_cursor = function(win)
  return { 5, 10 } -- line 5 (1-based), col 10 (0-based)
end

vim.api.nvim_buf_get_lines = function(buf, start, end_line, strict)
  return { "2025-01-01 open Assets:Checking USD" }
end

vim.api.nvim_buf_set_text = function(buf, start_row, start_col, end_row, end_col, replacement)
  -- Mock implementation for text editing
  return true
end

vim.api.nvim_win_set_cursor = function(win, pos)
  -- Mock cursor positioning
  return true
end

vim.split = function(str, sep)
  local result = {}
  local pattern = string.format("([^%s]+)", sep)
  for part in string.gmatch(str, pattern) do
    table.insert(result, part)
  end
  return result
end

-- Mock blink.cmp types
package.loaded["blink.cmp.types"] = {
  CompletionItemKind = {
    Text = 1,
    Function = 3,
    Variable = 6,
  },
}

-- Mock beancount.completion module
local mock_completion_items = {
  {
    label = "Assets:Checking",
    kind = 6,
    detail = "Asset account",
    insertText = "Assets:Checking",
    documentation = "Bank checking account",
  },
  {
    label = "USD",
    kind = 1,
    detail = "Currency",
    insertText = "USD",
  },
}

package.loaded["beancount.completion"] = {
  get_word_bounds = function(line, col)
    return 20, 23 -- Mock word boundaries
  end,
  get_completion_items = function(line, col)
    return mock_completion_items
  end,
}

-- Load the module to test
local blink = require("lua.beancount.completion.blink")

-- Test counter
local test_count = 0
local pass_count = 0

local function test(name, func)
  test_count = test_count + 1
  print(string.format("\n--- Test %d: %s ---", test_count, name))

  local success, error_msg = pcall(func)
  if success then
    pass_count = pass_count + 1
    print("✓ PASS")
  else
    print("✗ FAIL: " .. tostring(error_msg))
  end
end

local function assert_equal(actual, expected, message)
  if actual ~= expected then
    error(
      string.format("%s: expected '%s', got '%s'", message or "Assertion failed", tostring(expected), tostring(actual))
    )
  end
end

local function assert_not_nil(value, message)
  if value == nil then
    error(message or "Expected value to not be nil")
  end
end

local function assert_type(value, expected_type, message)
  if type(value) ~= expected_type then
    error(
      string.format("%s: expected type '%s', got '%s'", message or "Type assertion failed", expected_type, type(value))
    )
  end
end

-- Test M.new() function
test("M.new creates new instance", function()
  local instance = blink.new()
  assert_not_nil(instance, "Instance should not be nil")
  assert_type(instance, "table", "Instance should be a table")

  -- Check that instance has access to module methods via metatable
  assert_type(instance.get_completions, "function", "Instance should have get_completions method")
  assert_type(instance.resolve, "function", "Instance should have resolve method")
  assert_type(instance.execute, "function", "Instance should have execute method")
end)

-- Test M.get_completions() function
test("M.get_completions returns completion items", function()
  local instance = blink.new()
  local context = {
    cursor = { line = 4, character = 10 },
  }

  local callback_called = false
  local callback_result = nil

  local function callback(result)
    callback_called = true
    callback_result = result
  end

  instance:get_completions(context, callback)

  assert_equal(callback_called, true, "Callback should be called")
  assert_not_nil(callback_result, "Callback result should not be nil")
  assert_type(callback_result, "table", "Callback result should be a table")

  -- Check result structure
  assert_equal(callback_result.is_incomplete_forward, false, "is_incomplete_forward should be false")
  assert_equal(callback_result.is_incomplete_backward, false, "is_incomplete_backward should be false")
  assert_not_nil(callback_result.items, "Items should not be nil")
  assert_type(callback_result.items, "table", "Items should be a table")

  -- Check first item structure
  local first_item = callback_result.items[1]
  assert_not_nil(first_item, "First item should not be nil")
  assert_equal(first_item.label, "Assets:Checking", "First item label should match")
  assert_equal(first_item.kind, 6, "First item kind should match")
  assert_not_nil(first_item.textEdit, "First item should have textEdit")
  assert_not_nil(first_item.textEdit.range, "textEdit should have range")
  assert_not_nil(first_item.textEdit.newText, "textEdit should have newText")
end)

-- Test M.resolve() function
test("M.resolve returns item unchanged", function()
  local instance = blink.new()
  local test_item = {
    label = "Test Item",
    kind = 1,
    detail = "Test detail",
  }

  local callback_called = false
  local callback_result = nil

  local function callback(result)
    callback_called = true
    callback_result = result
  end

  instance:resolve(test_item, callback)

  assert_equal(callback_called, true, "Callback should be called")
  assert_equal(callback_result, test_item, "Resolved item should be the same as input")
end)

-- Test M.execute() function with textEdit
test("M.execute handles textEdit correctly", function()
  local instance = blink.new()
  local test_item = {
    label = "Assets:Checking",
  }

  local callback_data = {
    textEdit = {
      range = {
        start = { line = 0, character = 20 },
        ["end"] = { line = 0, character = 23 },
      },
      newText = "Assets:Checking",
    },
  }

  local function callback(result)
    -- Mock callback function
  end

  -- This should execute without errors
  instance:execute(test_item, callback_data)
end)

-- Test M.execute() function without textEdit
test("M.execute handles missing textEdit gracefully", function()
  local instance = blink.new()
  local test_item = {
    label = "Test Item",
  }

  local function callback(result)
    -- Mock callback function
  end

  -- This should execute without errors even without textEdit
  instance:execute(test_item, callback)
end)

-- Test edge cases
test("M.get_completions handles empty completion items", function()
  -- Temporarily override the mock to return empty items
  local original_get_completion_items = package.loaded["beancount.completion"].get_completion_items
  package.loaded["beancount.completion"].get_completion_items = function()
    return {}
  end

  local instance = blink.new()
  local context = { cursor = { line = 0, character = 0 } }

  local callback_called = false
  local callback_result = nil

  local function callback(result)
    callback_called = true
    callback_result = result
  end

  instance:get_completions(context, callback)

  assert_equal(callback_called, true, "Callback should be called")
  assert_not_nil(callback_result.items, "Items should not be nil")
  assert_equal(#callback_result.items, 0, "Items should be empty")

  -- Restore original mock
  package.loaded["beancount.completion"].get_completion_items = original_get_completion_items
end)

test("M.get_completions handles missing buffer lines", function()
  -- Temporarily override vim API to return empty lines
  local original_get_lines = vim.api.nvim_buf_get_lines
  vim.api.nvim_buf_get_lines = function()
    return {}
  end

  local instance = blink.new()
  local context = { cursor = { line = 0, character = 0 } }

  local callback_called = false
  local function callback(result)
    callback_called = true
  end

  -- Should not error even with missing lines
  instance:get_completions(context, callback)
  assert_equal(callback_called, true, "Callback should be called")

  -- Restore original mock
  vim.api.nvim_buf_get_lines = original_get_lines
end)

test("M.execute handles multiline newText", function()
  local instance = blink.new()
  local test_item = { label = "Test" }

  local callback_data = {
    textEdit = {
      range = {
        start = { line = 0, character = 0 },
        ["end"] = { line = 0, character = 4 },
      },
      newText = "line1\nline2\nline3",
    },
  }

  local function callback(result)
    -- Mock callback
  end

  -- Should handle multiline text without errors
  instance:execute(test_item, callback_data)
end)

-- Print test results
print(string.format("\n=== Test Results ==="))
print(string.format("Tests run: %d", test_count))
print(string.format("Tests passed: %d", pass_count))
print(string.format("Tests failed: %d", test_count - pass_count))

if pass_count == test_count then
  print("✓ All tests passed!\n")
  os.exit(0)
else
  print("✗ Some tests failed!\n")
  os.exit(1)
end
