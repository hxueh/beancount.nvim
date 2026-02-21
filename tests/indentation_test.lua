-- Tests for beancount ftplugin indentation behavior
-- Verifies that the plugin does NOT override user indentation settings

---@diagnostic disable-next-line: redundant-parameter
vim.opt.runtimepath:prepend(vim.fn.getcwd())

print("Running indentation tests...")

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

-- Verify ftplugin preserves user shiftwidth
run_test("should not override user shiftwidth=2", function()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_buf_set_option(bufnr, "shiftwidth", 2)
  vim.b.did_ftplugin = nil
  vim.cmd("source ftplugin/beancount.lua")
  test_assert(vim.api.nvim_buf_get_option(bufnr, "shiftwidth") == 2, "shiftwidth should remain 2")
  vim.api.nvim_buf_delete(bufnr, { force = true })
end)

-- Verify ftplugin preserves user tabstop
run_test("should not override user tabstop=2", function()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_buf_set_option(bufnr, "tabstop", 2)
  vim.b.did_ftplugin = nil
  vim.cmd("source ftplugin/beancount.lua")
  test_assert(vim.api.nvim_buf_get_option(bufnr, "tabstop") == 2, "tabstop should remain 2")
  vim.api.nvim_buf_delete(bufnr, { force = true })
end)

-- Verify ftplugin preserves user softtabstop
run_test("should not override user softtabstop=2", function()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_buf_set_option(bufnr, "softtabstop", 2)
  vim.b.did_ftplugin = nil
  vim.cmd("source ftplugin/beancount.lua")
  test_assert(vim.api.nvim_buf_get_option(bufnr, "softtabstop") == 2, "softtabstop should remain 2")
  vim.api.nvim_buf_delete(bufnr, { force = true })
end)

-- Verify ftplugin preserves user expandtab=false
run_test("should not override user expandtab=false", function()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_buf_set_option(bufnr, "expandtab", false)
  vim.b.did_ftplugin = nil
  vim.cmd("source ftplugin/beancount.lua")
  test_assert(vim.api.nvim_buf_get_option(bufnr, "expandtab") == false, "expandtab should remain false")
  vim.api.nvim_buf_delete(bufnr, { force = true })
end)

-- Verify ftplugin still sets commentstring correctly
run_test("should set commentstring to ';; %s'", function()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(bufnr)
  vim.b.did_ftplugin = nil
  vim.cmd("source ftplugin/beancount.lua")
  test_assert(vim.api.nvim_buf_get_option(bufnr, "commentstring") == ";; %s", "commentstring should be ';; %s'")
  vim.api.nvim_buf_delete(bufnr, { force = true })
end)

-- Verify ftplugin still sets foldmethod correctly
run_test("should set foldmethod to 'expr'", function()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(bufnr)
  vim.b.did_ftplugin = nil
  vim.cmd("source ftplugin/beancount.lua")
  test_assert(vim.wo.foldmethod == "expr", "foldmethod should be 'expr'")
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
