-- Comprehensive functional tests for beancount completion module
-- Tests the get_account_completions function with various scenarios
-- Run with: nvim --headless --noplugin --clean -c "luafile tests/completion_test.lua"

-- Add lua path to find beancount modules
---@diagnostic disable-next-line: redundant-parameter
vim.opt.runtimepath:prepend(vim.fn.getcwd())

print("Running comprehensive completion tests...")

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

-- Helper to get fresh completion module
local function get_completion()
  package.loaded["beancount.completion"] = nil
  return require("beancount.completion")
end

-- Mock vim.pesc function
vim.pesc = function(str)
  return str:gsub("[%(%)%.%+%-%*%?%[%]%^%$%%]", "%%%1")
end

-- Mock vim.notify to avoid errors
vim.notify = function(msg, level) end
vim.log = { levels = { ERROR = 4 } }

-- Test data setup
local test_accounts = {
  ["Assets:US:Bank"] = {
    balance = { "1000.00 USD" },
    open = "2025-01-01",
    currencies = { "USD" },
  },
  ["Assets:US:Brokers"] = {
    balance = { "5000.00 USD", "100 AAPL" },
    open = "2025-01-01",
    currencies = { "USD", "AAPL" },
  },
  ["Assets:Cash"] = {
    balance = { "200.00 USD" },
    open = "2025-01-01",
    currencies = { "USD" },
  },
  ["Assets:UK:Bank"] = {
    balance = { "500.00 GBP" },
    open = "2025-01-01",
    currencies = { "GBP" },
  },
  ["Liabilities:CreditCard"] = {
    balance = { "-1500.00 USD" },
    open = "2025-01-01",
    currencies = { "USD" },
  },
  ["Expenses:Food"] = {
    balance = {},
    open = "2025-01-01",
  },
  ["Income:Salary"] = {
    balance = { "-8000.00 USD" },
    open = "2025-01-01",
    currencies = { "USD" },
  },
  ["Assets:Closed:Account"] = {
    balance = { "0.00 USD" },
    open = "2025-01-01",
    close = "2025-06-01",
    currencies = { "USD" },
  },
}

-- Test 1: Basic module loading
run_test("should load completion module", function()
  local completion = get_completion()
  test_assert(completion ~= nil, "completion module should load")
  test_assert(type(completion.get_account_completions) == "function", "should have get_account_completions function")
end)

-- Test 2: Empty prefix completion
run_test("should return all accounts for empty prefix", function()
  local completion = get_completion()
  completion.completion_data.accounts = test_accounts

  local items = completion.get_account_completions("")
  test_assert(#items >= 7, "should return at least 7 accounts (excluding closed)")
  test_assert(items[1].label ~= nil, "items should have labels")
  test_assert(items[1].kind == 6, "items should have correct kind (Class)")
end)

-- Test 3: Simple prefix matching
run_test("should match accounts by prefix", function()
  local completion = get_completion()
  completion.completion_data.accounts = test_accounts

  local items = completion.get_account_completions("Assets")
  local asset_count = 0
  for _, item in ipairs(items) do
    if item.label:find("^Assets") then
      asset_count = asset_count + 1
    end
  end
  test_assert(asset_count >= 4, "should find at least 4 Asset accounts")
end)

-- Test 4: Prefix with colon but not ending with colon (the main fix)
run_test("should handle prefix with colon correctly (Assets:U)", function()
  local completion = get_completion()
  completion.completion_data.accounts = test_accounts

  local items = completion.get_account_completions("Assets:U")

  -- Should find Assets:US:Bank and Assets:US:Brokers
  local found_bank = false
  local found_brokers = false

  for _, item in ipairs(items) do
    if item.label == "Assets:US:Bank" then
      found_bank = true
      test_assert(
        item.insertText == "Assets:US:Bank",
        "should insert 'Assets:US:Bank' for Assets:US:Bank when prefix is 'Assets:U'"
      )
    elseif item.label == "Assets:US:Brokers" then
      found_brokers = true
      test_assert(
        item.insertText == "Assets:US:Brokers",
        "should insert 'Assets:US:Brokers' for Assets:US:Brokers when prefix is 'Assets:U'"
      )
    end
  end

  test_assert(found_bank, "should find Assets:US:Bank")
  test_assert(found_brokers, "should find Assets:US:Brokers")
end)

-- Test 5: Prefix ending with colon
run_test("should handle prefix ending with colon correctly (Assets:)", function()
  local completion = get_completion()
  completion.completion_data.accounts = test_accounts

  local items = completion.get_account_completions("Assets:")

  local found_items = {}
  for _, item in ipairs(items) do
    if item.label:find("^Assets:") then
      found_items[item.label] = item.insertText
    end
  end

  test_assert(
    found_items["Assets:US:Bank"] == "Assets:US:Bank",
    "should insert 'Assets:US:Bank' when prefix is 'Assets:'"
  )
  test_assert(found_items["Assets:Cash"] == "Assets:Cash", "should insert 'Assets:Cash' when prefix is 'Assets:'")
end)

-- Test 6: Deep nesting with partial match
run_test("should handle deep nesting (Assets:US:)", function()
  local completion = get_completion()
  completion.completion_data.accounts = test_accounts

  local items = completion.get_account_completions("Assets:US:")

  local found_items = {}
  for _, item in ipairs(items) do
    if item.label:find("^Assets:US:") then
      found_items[item.label] = item.insertText
    end
  end

  test_assert(
    found_items["Assets:US:Bank"] == "Assets:US:Bank",
    "should insert 'Assets:US:Bank' when prefix is 'Assets:US:'"
  )
  test_assert(
    found_items["Assets:US:Brokers"] == "Assets:US:Brokers",
    "should insert 'Assets:US:Brokers' when prefix is 'Assets:US:'"
  )
end)

-- Test 7: Partial match within colon segment
run_test("should handle partial match within segment (Assets:US:B)", function()
  local completion = get_completion()
  completion.completion_data.accounts = test_accounts

  local items = completion.get_account_completions("Assets:US:B")

  local found_items = {}
  for _, item in ipairs(items) do
    if item.label:find("^Assets:US:B") then
      found_items[item.label] = item.insertText
    end
  end

  test_assert(
    found_items["Assets:US:Bank"] == "Assets:US:Bank",
    "should insert 'Assets:US:Bank' when prefix is 'Assets:US:B'"
  )
  test_assert(
    found_items["Assets:US:Brokers"] == "Assets:US:Brokers",
    "should insert 'Assets:US:Brokers' when prefix is 'Assets:US:B'"
  )
end)

-- Test 8: Case insensitive matching
run_test("should handle case insensitive matching", function()
  local completion = get_completion()
  completion.completion_data.accounts = test_accounts

  local items = completion.get_account_completions("assets:us")

  local found_bank = false
  for _, item in ipairs(items) do
    if item.label == "Assets:US:Bank" then
      found_bank = true
      test_assert(
        item.insertText == "Assets:US:Bank",
        "should insert 'Assets:US:Bank' for lowercase prefix 'assets:us'"
      )
    end
  end

  test_assert(found_bank, "should find Assets:US:Bank with lowercase prefix")
end)

-- Test 9: Closed accounts exclusion
run_test("should exclude closed accounts with zero balance", function()
  local completion = get_completion()
  completion.completion_data.accounts = test_accounts

  local items = completion.get_account_completions("Assets:Closed")

  local found_closed = false
  for _, item in ipairs(items) do
    if item.label == "Assets:Closed:Account" then
      found_closed = true
    end
  end

  test_assert(not found_closed, "should not find closed account with zero balance")
end)

-- Test 10: Account details in completion items
run_test("should include account details", function()
  local completion = get_completion()
  completion.completion_data.accounts = test_accounts

  local items = completion.get_account_completions("Assets:US:Bank")

  local found_item = nil
  for _, item in ipairs(items) do
    if item.label == "Assets:US:Bank" then
      found_item = item
      break
    end
  end

  test_assert(found_item ~= nil, "should find the account")
  test_assert(found_item.detail ~= nil, "should have detail information")
  test_assert(found_item.detail:find("Balance:"), "should include balance information")
  test_assert(found_item.detail:find("Opened:"), "should include opened date")
end)

-- Test 11: No matches scenario
run_test("should handle no matches gracefully", function()
  local completion = get_completion()
  completion.completion_data.accounts = test_accounts

  local items = completion.get_account_completions("NonExistent:Account")
  test_assert(#items == 0, "should return empty list for non-existent accounts")
end)

-- Test 12: Nil prefix handling
run_test("should handle nil prefix", function()
  local completion = get_completion()
  completion.completion_data.accounts = test_accounts

  local items = completion.get_account_completions(nil)
  test_assert(#items >= 7, "should return at least 7 accounts for nil prefix (excluding closed)")
end)

-- Test 13: Contains match (fallback)
run_test("should find accounts by contains match", function()
  local completion = get_completion()
  completion.completion_data.accounts = test_accounts

  local items = completion.get_account_completions("Bank")

  local found_matches = 0
  for _, item in ipairs(items) do
    if item.label:find("Bank") then
      found_matches = found_matches + 1
    end
  end

  test_assert(found_matches >= 2, "should find at least 2 accounts containing 'Bank'")
end)

-- Test 14: Multiple colon segments
run_test("should handle multiple colon segments correctly", function()
  -- Add a deeper nested account for this test
  local extended_accounts = vim.deepcopy(test_accounts)
  extended_accounts["Assets:US:Bank:Checking:Primary"] = {
    balance = { "2000.00 USD" },
    open = "2025-01-01",
    currencies = { "USD" },
  }

  local completion = get_completion()
  completion.completion_data.accounts = extended_accounts

  local items = completion.get_account_completions("Assets:US:Bank:Check")

  local found_item = nil
  for _, item in ipairs(items) do
    if item.label == "Assets:US:Bank:Checking:Primary" then
      found_item = item
      break
    end
  end

  test_assert(found_item ~= nil, "should find deeply nested account")
  test_assert(
    found_item.insertText == "Assets:US:Bank:Checking:Primary",
    "should insert full account name for deep nesting"
  )
end)

-- Test 15: Edge case - single character after colon
run_test("should handle single character after colon", function()
  local completion = get_completion()
  completion.completion_data.accounts = test_accounts

  local items = completion.get_account_completions("Assets:C")

  local found_cash = false
  for _, item in ipairs(items) do
    if item.label == "Assets:Cash" then
      found_cash = true
      test_assert(item.insertText == "Assets:Cash", "should insert 'Assets:Cash' for prefix 'Assets:C'")
    end
  end

  test_assert(found_cash, "should find Assets:Cash")
end)

-- Test 16: Comprehensive user scenarios (all typing stages)
run_test("should handle all typing stages correctly", function()
  local completion = get_completion()
  completion.completion_data.accounts = test_accounts

  local typing_stages = { "A", "Assets:", "Assets:U", "Assets:US", "Assets:US:", "Assets:US:B", "Assets:US:Bank" }

  for _, stage in ipairs(typing_stages) do
    local items = completion.get_account_completions(stage)

    -- Each stage should return some completions (except maybe the final exact match)
    if stage == "Assets:US:Bank" then
      test_assert(#items >= 1, "Final stage should find exact match: " .. stage)
    else
      test_assert(#items >= 1, "Should find completions for stage: " .. stage)
    end

    -- All completions should return full account names as insertText
    for _, item in ipairs(items) do
      test_assert(item.insertText == item.label, "insertText should equal label for " .. stage .. " -> " .. item.label)
    end
  end
end)

-- Test 17: Context detection accuracy
run_test("should detect account context correctly", function()
  local completion = get_completion()

  local context_tests = {
    { line = "Assets:U",            col = 9,  expected = true },
    { line = "  Assets:U",          col = 11, expected = true },
    { line = '2025-01-01 * "Test"', col = 20, expected = false },
    { line = "open Assets:U",       col = 14, expected = true },
  }

  for _, test in ipairs(context_tests) do
    local result = completion.is_account_context(test.line, test.col)
    test_assert(result == test.expected, "Context detection failed for: '" .. test.line .. "' at col " .. test.col)
  end
end)

-- Test 18: User experience simulation (the original bug)
run_test("should simulate complete user experience correctly", function()
  local completion = get_completion()
  completion.completion_data.accounts = test_accounts

  -- Simulate user typing "Assets:U" in a posting line
  local typed_text = "Assets:U"
  local line = "  " .. typed_text -- Indented posting line
  local cursor_pos = #line + 1

  -- Get completions via the main interface
  local items = completion.get_completion_items(line, cursor_pos)

  -- Should find account completions
  local account_items = {}
  for _, item in ipairs(items) do
    if item.kind == 6 then -- Account kind
      table.insert(account_items, item)
    end
  end

  test_assert(#account_items >= 2, "Should find at least 2 account completions")

  -- Find the target account
  local target_item = nil
  for _, item in ipairs(account_items) do
    if item.label == "Assets:US:Bank" then
      target_item = item
      break
    end
  end

  test_assert(target_item ~= nil, "Should find Assets:US:Bank in completions")
  test_assert(target_item.insertText == "Assets:US:Bank", "insertText should be full account name")

  -- Simulate text replacement
  local word_start, _ = completion.get_word_bounds(line, cursor_pos)
  local prefix_part = line:sub(1, word_start - 1)
  local final_result = prefix_part .. target_item.insertText
  local expected_result = "  Assets:US:Bank"

  test_assert(
    final_result == expected_result,
    "Text replacement should result in complete account name. Got: " .. final_result
  )
end)

-- Test 19: Case insensitive comprehensive test
run_test("should handle case insensitive matching comprehensively", function()
  local completion = get_completion()
  completion.completion_data.accounts = test_accounts

  local case_variants = { "assets:us", "ASSETS:US", "Assets:us", "assets:US", "AsSeTs:uS" }

  for _, variant in ipairs(case_variants) do
    local items = completion.get_account_completions(variant)

    local found_bank = false
    for _, item in ipairs(items) do
      if item.label == "Assets:US:Bank" then
        found_bank = true
        test_assert(
          item.insertText == "Assets:US:Bank",
          "Case insensitive match should return full account name for: " .. variant
        )
        break
      end
    end

    test_assert(found_bank, "Should find Assets:US:Bank for case variant: " .. variant)
  end
end)

-- Test 20: Integration with blink completion workflow
run_test("should integrate correctly with blink completion workflow", function()
  local completion = get_completion()
  completion.completion_data.accounts = test_accounts

  -- Test the complete workflow as blink.cmp would use it
  local test_scenarios = {
    { line = "  Assets:U",          col = 11, expected_accounts = 3 },
    { line = "open Assets:U",       col = 14, expected_accounts = 3 },
    { line = "balance Assets:US:B", col = 20, expected_accounts = 2 },
  }

  for _, scenario in ipairs(test_scenarios) do
    -- This simulates what blink.lua would call
    local items = completion.get_completion_items(scenario.line, scenario.col)

    local account_count = 0
    local all_have_correct_insert_text = true

    for _, item in ipairs(items) do
      if item.kind == 6 then -- Account kind
        account_count = account_count + 1
        if item.insertText ~= item.label then
          all_have_correct_insert_text = false
        end
      end
    end

    test_assert(
      account_count >= scenario.expected_accounts - 1,
      "Should find expected account completions for: " .. scenario.line
    )
    test_assert(all_have_correct_insert_text, "All account completions should have insertText equal to label")
  end
end)

-- Print test results
print("\nTest Summary:")
print("Tests run: " .. tests_run)
print("Tests passed: " .. tests_passed)
print("Tests failed: " .. (tests_run - tests_passed))

if tests_passed == tests_run then
  print("✓ All tests passed!\n")
  os.exit(0)
else
  print("✗ Some tests failed!\n")
  os.exit(1)
end
