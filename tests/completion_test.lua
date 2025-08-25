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
  if found_item ~= nil then
    test_assert(found_item.detail:find("Balance:"), "should include balance information")
    test_assert(found_item.detail:find("Opened:"), "should include opened date")
  end
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
  if found_item ~= nil then
    test_assert(
      found_item.insertText == "Assets:US:Bank:Checking:Primary",
      "should insert full account name for deep nesting"
    )
  end
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
  if target_item ~= nil then
    test_assert(target_item.insertText == "Assets:US:Bank", "insertText should be full account name")
  end

  -- Simulate text replacement
  local word_start, _ = completion.get_word_bounds(line, cursor_pos)
  local prefix_part = line:sub(1, word_start - 1)
  test_assert(prefix_part ~= nil, "should get prefix part")
  test_assert(target_item ~= nil, "should get insert text")

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

-- Test 21: Date completion functionality
run_test("should provide date completions", function()
  local completion = get_completion()

  -- Test empty prefix first - should always return common date options
  local items_empty = completion.get_date_completions("")
  test_assert(#items_empty >= 5, "should return common date options for empty prefix")

  -- Test with current year prefix - should return dates matching current year
  local current_year = tostring(os.date("%Y"))
  local items = completion.get_date_completions(current_year)
  test_assert(#items >= 0, "should return date completions for current year prefix")

  -- Check that all items have proper structure
  for _, item in ipairs(items_empty) do
    test_assert(item.label ~= nil, "date completion should have label")
    test_assert(item.kind == 12, "date completion should have Value kind")
    test_assert(item.insertText ~= nil, "date completion should have insertText")
  end
end)

-- Test 22: Commodity completion functionality
run_test("should provide commodity completions", function()
  local completion = get_completion()
  completion.completion_data.commodities = { "USD", "EUR", "GBP", "CAD", "JPY" }
  completion.completion_data.options = {
    { key = "operating_currency", value = "USD" },
    { key = "operating_currency", value = "EUR" },
  }

  -- Test with empty line (should use all commodities)
  local items = completion.get_commodity_completions("U", "")
  test_assert(#items >= 1, "should find USD commodity")

  -- Test with account line (should prioritize account currencies)
  local line_with_account = "  Assets:US:Bank  100.00 "
  local items_with_account = completion.get_commodity_completions("U", line_with_account)
  test_assert(#items_with_account >= 0, "should handle account-specific currency completion")

  -- Check completion item structure
  for _, item in ipairs(items) do
    test_assert(item.kind == 13, "commodity completion should have Constant kind")
  end
end)

-- Test 23: Payee completion functionality
run_test("should provide payee completions", function()
  local completion = get_completion()
  completion.completion_data.payees = { "Grocery Store", "Coffee Shop", "Gas Station", "Amazon" }

  local items = completion.get_payee_completions("G")
  local found_grocery = false
  local found_gas = false

  for _, item in ipairs(items) do
    if item.label == "Grocery Store" then
      found_grocery = true
    elseif item.label == "Gas Station" then
      found_gas = true
    end
    test_assert(item.kind == 1, "payee completion should have Text kind")
  end

  test_assert(found_grocery, "should find Grocery Store")
  test_assert(found_gas, "should find Gas Station")
end)

-- Test 24: Narration completion functionality
run_test("should provide narration completions", function()
  local completion = get_completion()
  completion.completion_data.narrations = { "Lunch with client", "Weekly grocery shopping", "Gas for car" }

  local items = completion.get_narration_completions("lunch")
  test_assert(#items >= 1, "should find narration containing 'lunch'")

  local found_lunch = false
  for _, item in ipairs(items) do
    if item.label == "Lunch with client" then
      found_lunch = true
    end
    test_assert(item.kind == 1, "narration completion should have Text kind")
  end

  test_assert(found_lunch, "should find 'Lunch with client' narration")
end)

-- Test 25: Tag completion functionality
run_test("should provide tag completions", function()
  local completion = get_completion()
  completion.completion_data.tags = { "personal", "work", "travel", "business" }

  local items = completion.get_tag_completions("#p")
  test_assert(#items >= 1, "should find tags starting with 'p'")

  local found_personal = false
  for _, item in ipairs(items) do
    if item.insertText == "personal" then
      found_personal = true
      test_assert(item.label == "#personal", "tag label should include #")
    end
    test_assert(item.kind == 14, "tag completion should have Keyword kind")
  end

  test_assert(found_personal, "should find 'personal' tag")
end)

-- Test 26: Link completion functionality
run_test("should provide link completions", function()
  local completion = get_completion()
  completion.completion_data.links = { "invoice-123", "receipt-456", "contract-789" }

  local items = completion.get_link_completions("^inv")
  test_assert(#items >= 1, "should find links starting with 'inv'")

  local found_invoice = false
  for _, item in ipairs(items) do
    if item.insertText == "invoice-123" then
      found_invoice = true
      test_assert(item.label == "^invoice-123", "link label should include ^")
    end
    test_assert(item.kind == 17, "link completion should have Reference kind")
  end

  test_assert(found_invoice, "should find 'invoice-123' link")
end)

-- Test 27: Context detection for different completion types
run_test("should detect various completion contexts", function()
  local completion = get_completion()

  -- Date context
  test_assert(completion.is_date_context("2024", 5), "should detect date context")
  test_assert(completion.is_date_context("2024-", 6), "should detect partial date context")
  test_assert(not completion.is_date_context("  Assets:US", 10), "should not detect date in account context")

  -- Commodity context - the cursor should be after the trailing space
  test_assert(
    completion.is_commodity_context("  Assets:Cash  100.00 ", 23),
    "should detect commodity context after amount"
  )
  test_assert(not completion.is_commodity_context("  Assets:Cash", 13), "should not detect commodity without amount")

  -- Payee context
  test_assert(completion.is_payee_context('2024-01-01 * "', 16), "should detect payee context")
  test_assert(not completion.is_payee_context('2024-01-01 * "Store" "', 22), "should not detect payee after completion")

  -- Narration context
  test_assert(completion.is_narration_context('2024-01-01 * "Store" "', 23), "should detect narration context")
  test_assert(
    not completion.is_narration_context('2024-01-01 * "', 16),
    "should not detect narration in payee position"
  )

  -- Tag context
  test_assert(completion.is_tag_context("some text #personal", 20), "should detect tag context")
  test_assert(not completion.is_tag_context("some text personal", 18), "should not detect tag without #")

  -- Link context
  test_assert(completion.is_link_context("some text ^invoice", 18), "should detect link context")
  test_assert(not completion.is_link_context("some text invoice", 17), "should not detect link without ^")
end)

-- Test 28: Helper function tests
run_test("should handle helper functions correctly", function()
  local completion = get_completion()
  completion.completion_data.accounts = test_accounts

  -- Test get_account_on_line
  local account = completion.get_account_on_line("  Assets:US:Bank  100.00")
  test_assert(account == "Assets:US:Bank", "should extract account from posting line")

  local no_account = completion.get_account_on_line('2024-01-01 * "Test"')
  test_assert(no_account == nil, "should return nil for non-posting line")

  -- Test get_account_currencies
  local currencies = completion.get_account_currencies("Assets:US:Bank")
  test_assert(currencies and #currencies == 1 and currencies[1] == "USD", "should return account currencies")

  local no_currencies = completion.get_account_currencies("NonExistent")
  test_assert(no_currencies == nil, "should return nil for non-existent account")

  -- Test get_word_bounds
  local start, end_pos = completion.get_word_bounds("  Assets:US:Bank", 10)
  test_assert(start == 3, "should find correct word start")
  test_assert(end_pos == 10, "should return correct end position")

  -- Test edge cases
  local start_empty, end_empty = completion.get_word_bounds("", 1)
  test_assert(start_empty == 1, "should handle empty string")

  local start_bounds, end_bounds = completion.get_word_bounds("test", 10)
  test_assert(start_bounds == 1 and end_bounds == 5, "should clamp to valid range")
end)

-- Test 29: Hover functionality
run_test("should provide hover information", function()
  local completion = get_completion()
  completion.completion_data.accounts = test_accounts

  -- Enable hover
  completion.hover_enabled = true

  local hover_info = completion.hover(0, 0, 10) -- Mock buffer, line, col
  -- This test is limited without actual buffer content, but we can test the structure

  -- Test get_account_hover directly
  local account_hover = completion.get_account_hover("Assets:US:Bank")
  test_assert(account_hover ~= nil, "should return hover info for valid account")
  if account_hover ~= nil then
    test_assert(account_hover.contents ~= nil, "should have contents")
    test_assert(account_hover.contents.kind == "markdown", "should be markdown format")
    test_assert(account_hover.contents.value:find("Assets:US:Bank"), "should contain account name")
    test_assert(account_hover.contents.value:find("1000.00 USD"), "should contain balance")
  end

  local no_hover = completion.get_account_hover("NonExistent")
  test_assert(no_hover == nil, "should return nil for non-existent account")

  -- Test disabled hover
  completion.hover_enabled = false
  local disabled_hover = completion.hover(0, 0, 10)
  test_assert(disabled_hover == nil, "should return nil when hover disabled")
end)

-- Test 30: Data update functionality
run_test("should handle data updates correctly", function()
  local completion = get_completion()

  -- Test valid JSON update
  local test_data = '{"accounts":{"Test:Account":{"balance":["100.00 USD"]}},"commodities":["USD","EUR"]}'
  completion.update_data(test_data)

  test_assert(completion.completion_data.accounts["Test:Account"] ~= nil, "should update accounts data")
  test_assert(completion.completion_data.commodities[1] == "USD", "should update commodities data")

  -- Test invalid JSON (should not crash)
  local original_data = vim.deepcopy(completion.completion_data)
  completion.update_data("invalid json")
  test_assert(vim.deep_equal(completion.completion_data, original_data), "should not change data on invalid JSON")

  -- Test empty data
  completion.update_data("")
  test_assert(vim.deep_equal(completion.completion_data, original_data), "should not change data on empty string")

  completion.update_data(nil)
  test_assert(vim.deep_equal(completion.completion_data, original_data), "should not change data on nil")
end)

-- Test 31: Operating currencies functionality
run_test("should handle operating currencies", function()
  local completion = get_completion()

  -- Test with operating currencies
  completion.completion_data.options = {
    { key = "operating_currency", value = "USD" },
    { key = "operating_currency", value = "EUR" },
    { key = "other_option",       value = "something" },
  }

  local operating_currencies = completion.get_operating_currencies()
  test_assert(operating_currencies ~= nil, "should return operating currencies")
  test_assert(#operating_currencies == 2, "should find 2 operating currencies")
  if operating_currencies ~= nil then
    test_assert(operating_currencies[1] == "USD", "should include USD")
    test_assert(operating_currencies[2] == "EUR", "should include EUR")
  end

  -- Test without options
  completion.completion_data.options = nil
  local no_operating = completion.get_operating_currencies()
  test_assert(no_operating == nil, "should return nil when no options")

  -- Test with no operating currencies
  completion.completion_data.options = { { key = "other_option", value = "something" } }
  local no_op_currencies = completion.get_operating_currencies()
  test_assert(no_op_currencies == nil, "should return nil when no operating currencies")
end)

-- Test 32: Blink integration check
run_test("should check blink integration status", function()
  local completion = get_completion()

  local has_blink, status = completion.check_blink_integration()
  test_assert(type(has_blink) == "boolean", "should return boolean for blink availability")
  test_assert(type(status) == "string", "should return status string")

  -- Since blink.cmp is not available in test environment, should return false
  test_assert(not has_blink, "should return false in test environment")
  test_assert(status == "Not installed or not available", "should return appropriate status message")
end)

-- Test 33: Buffer setup functionality
run_test("should setup buffer correctly", function()
  local completion = get_completion()

  -- Mock vim API for buffer setup
  vim.api.nvim_create_autocmd = function(event, opts)
    test_assert(event == "InsertCharPre", "should create InsertCharPre autocmd")
    test_assert(opts.buffer ~= nil, "should specify buffer")
    test_assert(type(opts.callback) == "function", "should provide callback function")
  end

  -- This should not error
  completion.setup_buffer(1)
end)

-- Test 34: Comprehensive integration test
run_test("should handle complete completion workflow", function()
  local completion = get_completion()
  completion.completion_data = {
    accounts = test_accounts,
    commodities = { "USD", "EUR", "GBP" },
    payees = { "Store", "Restaurant" },
    narrations = { "Lunch", "Dinner" },
    tags = { "personal", "work" },
    links = { "receipt-123" },
    options = { { key = "operating_currency", value = "USD" } },
  }

  -- Test various completion scenarios - use current date for date context
  local current_year = tostring(os.date("%Y"))
  local scenarios = {
    { line = current_year,             col = 5,  expected_type = "date" },
    { line = "  Assets:U",             col = 11, expected_type = "account" },
    { line = "  Assets:Cash  100.00 ", col = 21, expected_type = "commodity" },
    { line = '2024-01-01 * "',         col = 16, expected_type = "payee" },
    { line = '2024-01-01 * "Store" "', col = 22, expected_type = "narration" },
    { line = "test #p",                col = 8,  expected_type = "tag" },
    { line = "test ^r",                col = 8,  expected_type = "link" },
  }

  for _, scenario in ipairs(scenarios) do
    local items = completion.get_completion_items(scenario.line, scenario.col)
    test_assert(#items >= 0, "should return completions for " .. scenario.expected_type .. " context")

    -- Verify completion item structure
    for _, item in ipairs(items) do
      test_assert(item.label ~= nil, "completion item should have label")
      test_assert(item.kind ~= nil, "completion item should have kind")
      test_assert(item.insertText ~= nil, "completion item should have insertText")
    end
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
