-- Comprehensive functional tests for beancount indentation settings
-- Tests indentation configuration in ftplugin

-- Add lua path to find beancount modules
---@diagnostic disable-next-line: redundant-parameter
vim.opt.runtimepath:prepend(vim.fn.getcwd())

print("Running comprehensive indentation tests...")

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

-- Test buffer options after loading ftplugin
run_test("should set shiftwidth to 4", function()
  -- Create a new buffer and set it as current
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_buf_set_option(bufnr, "filetype", "beancount")

  -- Source the ftplugin directly
  vim.cmd("source ftplugin/beancount.lua")

  -- Check that shiftwidth is set to 4
  test_assert(vim.api.nvim_buf_get_option(bufnr, "shiftwidth") == 4, "shiftwidth should be 4")

  -- Clean up
  vim.api.nvim_buf_delete(bufnr, { force = true })
end)

run_test("should set tabstop to 4", function()
  -- Create a new buffer and set it as current
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_buf_set_option(bufnr, "filetype", "beancount")

  -- Source the ftplugin directly
  vim.cmd("source ftplugin/beancount.lua")

  -- Check that tabstop is set to 4
  test_assert(vim.api.nvim_buf_get_option(bufnr, "tabstop") == 4, "tabstop should be 4")

  -- Clean up
  vim.api.nvim_buf_delete(bufnr, { force = true })
end)

run_test("should set softtabstop to 4", function()
  -- Create a new buffer and set it as current
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_buf_set_option(bufnr, "filetype", "beancount")

  -- Source the ftplugin directly
  vim.cmd("source ftplugin/beancount.lua")

  -- Check that softtabstop is set to 4
  test_assert(vim.api.nvim_buf_get_option(bufnr, "softtabstop") == 4, "softtabstop should be 4")

  -- Clean up
  vim.api.nvim_buf_delete(bufnr, { force = true })
end)

run_test("should have expandtab enabled", function()
  -- Create a new buffer and set it as current
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_buf_set_option(bufnr, "filetype", "beancount")

  -- Source the ftplugin directly
  vim.cmd("source ftplugin/beancount.lua")

  -- Check that expandtab is enabled
  test_assert(vim.api.nvim_buf_get_option(bufnr, "expandtab") == true, "expandtab should be true")

  -- Clean up
  vim.api.nvim_buf_delete(bufnr, { force = true })
end)

run_test("should handle multiple buffer setups correctly", function()
  -- Create and setup first buffer
  local bufnr1 = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(bufnr1)
  vim.api.nvim_buf_set_option(bufnr1, "filetype", "beancount")
  vim.cmd("source ftplugin/beancount.lua")

  -- Create and setup second buffer
  local bufnr2 = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(bufnr2)
  vim.api.nvim_buf_set_option(bufnr2, "filetype", "beancount")
  vim.cmd("source ftplugin/beancount.lua")

  -- Check both buffers have correct settings
  test_assert(vim.api.nvim_buf_get_option(bufnr1, "shiftwidth") == 4, "buffer1 shiftwidth should be 4")
  test_assert(vim.api.nvim_buf_get_option(bufnr2, "shiftwidth") == 4, "buffer2 shiftwidth should be 4")
  test_assert(vim.api.nvim_buf_get_option(bufnr1, "tabstop") == 4, "buffer1 tabstop should be 4")
  test_assert(vim.api.nvim_buf_get_option(bufnr2, "tabstop") == 4, "buffer2 tabstop should be 4")

  -- Clean up
  vim.api.nvim_buf_delete(bufnr1, { force = true })
  vim.api.nvim_buf_delete(bufnr2, { force = true })
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
