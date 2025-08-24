-- Comprehensive functional tests for beancount symbols module
-- Tests all symbol parsing functionality without complex test framework

-- Add lua path to find beancount modules
---@diagnostic disable-next-line: redundant-parameter
vim.opt.runtimepath:prepend(vim.fn.getcwd())

print("Running comprehensive symbols tests...")

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

-- Helper to get fresh symbols module
local function get_symbols()
  package.loaded["beancount.symbols"] = nil
  return require("beancount.symbols")
end

-- Mock vim.api functions for testing
local original_nvim_get_current_buf = vim.api.nvim_get_current_buf
local original_nvim_buf_get_lines = vim.api.nvim_buf_get_lines

-- Test 1: Basic module loading
run_test("should load symbols module", function()
  local symbols = get_symbols()
  test_assert(type(symbols) == "table", "symbols should be a table")
  test_assert(type(symbols.get_document_symbols) == "function", "get_document_symbols should be a function")
  test_assert(type(symbols.parse_line_for_symbol) == "function", "parse_line_for_symbol should be a function")
  test_assert(type(symbols.show_document_symbols) == "function", "show_document_symbols should be a function")
  test_assert(type(symbols.setup) == "function", "setup should be a function")
  test_assert(type(symbols.setup_buffer) == "function", "setup_buffer should be a function")
end)

-- Test 2: Parse transaction with flag *
run_test("should parse completed transaction", function()
  local symbols = get_symbols()
  local symbol = symbols.parse_line_for_symbol('2024-01-15 * "Grocery Store" "Weekly shopping"', 0)

  test_assert(symbol ~= nil, "should return symbol for transaction")
  if symbol then
    test_assert(symbol.name == "[2024-01-15] Grocery Store", "should format transaction name correctly")
    test_assert(symbol.detail:find("Completed"), "should include complete detail")
    test_assert(symbol.detail:find("Grocery Store"), "should include payee in detail")
    test_assert(symbol.detail:find("Weekly shopping"), "should include narration in detail")
    test_assert(symbol.kind == 24, "should use Event symbol kind")
    test_assert(symbol.range.start.line == 0, "should have correct start line")
    test_assert(symbol.range.start.character == 0, "should have correct start character")
  end
end)

-- Test 3: Parse transaction with flag !
run_test("should parse incomplete transaction", function()
  local symbols = get_symbols()
  local symbol = symbols.parse_line_for_symbol('2024-01-15 ! "Restaurant" "Lunch meeting"', 0)

  test_assert(symbol ~= nil, "should return symbol for incomplete transaction")
  if symbol then
    test_assert(symbol.name == "[2024-01-15] Restaurant", "should format incomplete transaction name correctly")
    test_assert(symbol.detail:find("Incomplete"), "should include incomplete detail")
    test_assert(symbol.detail:find("Restaurant"), "should include payee in detail")
    test_assert(symbol.detail:find("Lunch meeting"), "should include narration in detail")
    test_assert(symbol.kind == 24, "should use Event symbol kind")
  end
end)

-- Test 4: Parse transaction with only payee
run_test("should parse transaction with only payee", function()
  local symbols = get_symbols()
  local symbol = symbols.parse_line_for_symbol('2024-01-15 * "Coffee Shop"', 0)

  test_assert(symbol ~= nil, "should return symbol for payee-only transaction")
  if symbol then
    test_assert(symbol.name == "[2024-01-15] Coffee Shop", "should format payee-only name correctly")
    test_assert(symbol.detail:find("Completed: Coffee Shop"), "should include payee in detail")
  end
end)

-- Test 5: Parse transaction with only narration
run_test("should parse transaction with only narration", function()
  local symbols = get_symbols()
  local symbol = symbols.parse_line_for_symbol('2024-01-15 * "" "Bus fare"', 0)

  test_assert(symbol ~= nil, "should return symbol for narration-only transaction")
  if symbol then
    test_assert(symbol.name == "[2024-01-15] Bus fare", "should format narration-only name correctly")
    test_assert(symbol.detail:find("Completed: Bus fare"), "should include narration in detail")
  end
end)

-- Test 6: Parse account opening
run_test("should parse account opening", function()
  local symbols = get_symbols()
  local symbol = symbols.parse_line_for_symbol("2024-01-01 open Assets:Cash USD", 0)

  test_assert(symbol ~= nil, "should return symbol for account opening")
  if symbol then
    test_assert(symbol.name == "Assets:Cash", "should extract account name")
    test_assert(symbol.detail == "Open account (USD)", "should include currency in detail")
    test_assert(symbol.kind == 5, "should use Class symbol kind")
  end
end)

-- Test 7: Parse account opening without currency
run_test("should parse account opening without currency", function()
  local symbols = get_symbols()
  local symbol = symbols.parse_line_for_symbol("2024-01-01 open Equity:OpeningBalances", 0)

  test_assert(symbol ~= nil, "should return symbol for account opening without currency")
  if symbol then
    test_assert(symbol.name == "Equity:OpeningBalances", "should extract account name")
    test_assert(symbol.detail == "Open account", "should have basic detail without currency")
    test_assert(symbol.kind == 5, "should use Class symbol kind")
  end
end)

-- Test 8: Parse account closing
run_test("should parse account closing", function()
  local symbols = get_symbols()
  local symbol = symbols.parse_line_for_symbol("2024-12-31 close Assets:Cash", 0)

  test_assert(symbol ~= nil, "should return symbol for account closing")
  if symbol then
    test_assert(symbol.name == "Assets:Cash", "should extract account name")
    test_assert(symbol.detail == "Close account", "should have close account detail")
    test_assert(symbol.kind == 5, "should use Class symbol kind")
  end
end)

-- Test 9: Parse commodity definition
run_test("should parse commodity definition", function()
  local symbols = get_symbols()
  local symbol = symbols.parse_line_for_symbol("2024-01-01 commodity USD", 0)

  test_assert(symbol ~= nil, "should return symbol for commodity")
  if symbol then
    test_assert(symbol.name == "USD", "should extract commodity name")
    test_assert(symbol.detail == "Commodity definition", "should have commodity detail")
    test_assert(symbol.kind == 14, "should use Constant symbol kind")
  end
end)

-- Test 10: Parse price definition
run_test("should parse price definition", function()
  local symbols = get_symbols()
  local symbol = symbols.parse_line_for_symbol("2024-01-15 price BTC 45000.00 USD", 0)

  test_assert(symbol ~= nil, "should return symbol for price")
  if symbol then
    test_assert(symbol.name == "BTC @ 45000.00 USD", "should format price correctly")
    test_assert(symbol.detail == "Price definition", "should have price detail")
    test_assert(symbol.kind == 16, "should use Number symbol kind")
  end
end)

-- Test 11: Parse balance assertion
run_test("should parse balance assertion", function()
  local symbols = get_symbols()
  local symbol = symbols.parse_line_for_symbol("2024-01-31 balance Assets:Cash 1000.00 USD", 0)

  test_assert(symbol ~= nil, "should return symbol for balance")
  if symbol then
    test_assert(symbol.name == "Assets:Cash: 1000.00 USD", "should format balance correctly")
    test_assert(symbol.detail == "Balance assertion", "should have balance detail")
    test_assert(symbol.kind == 7, "should use Property symbol kind")
  end
end)

-- Test 12: Parse option directive
run_test("should parse option directive", function()
  local symbols = get_symbols()
  local symbol = symbols.parse_line_for_symbol('option "title" "My Ledger"', 0)

  test_assert(symbol ~= nil, "should return symbol for option")
  if symbol then
    test_assert(symbol.name == "title", "should extract option name")
    test_assert(symbol.detail == "Option: My Ledger", "should include option value")
    test_assert(symbol.kind == 13, "should use Variable symbol kind")
  end
end)

-- Test 13: Parse plugin directive
run_test("should parse plugin directive", function()
  local symbols = get_symbols()
  local symbol = symbols.parse_line_for_symbol('plugin "beancount.plugins.auto_accounts"', 0)

  test_assert(symbol ~= nil, "should return symbol for plugin")
  if symbol then
    test_assert(symbol.name == "beancount.plugins.auto_accounts", "should extract plugin name")
    test_assert(symbol.detail == "Plugin", "should have plugin detail")
    test_assert(symbol.kind == 2, "should use Module symbol kind")
  end
end)

-- Test 14: Parse include directive
run_test("should parse include directive", function()
  local symbols = get_symbols()
  local symbol = symbols.parse_line_for_symbol('include "accounts.bean"', 0)

  test_assert(symbol ~= nil, "should return symbol for include")
  if symbol then
    test_assert(symbol.name == "accounts.bean", "should extract include filename")
    test_assert(symbol.detail == "Include file", "should have include detail")
    test_assert(symbol.kind == 1, "should use File symbol kind")
  end
end)

-- Test 15: Handle empty lines
run_test("should handle empty lines", function()
  local symbols = get_symbols()
  local symbol = symbols.parse_line_for_symbol("", 0)
  test_assert(symbol == nil, "should return nil for empty line")

  local symbol2 = symbols.parse_line_for_symbol("   ", 0)
  test_assert(symbol2 == nil, "should return nil for whitespace-only line")
end)

-- Test 16: Handle comment lines
run_test("should handle comment lines", function()
  local symbols = get_symbols()
  local symbol = symbols.parse_line_for_symbol("; This is a comment", 0)
  test_assert(symbol == nil, "should return nil for comment line")

  local symbol2 = symbols.parse_line_for_symbol("  ; Indented comment", 0)
  test_assert(symbol2 == nil, "should return nil for indented comment line")
end)

-- Test 17: Handle invalid transaction format
run_test("should handle invalid lines gracefully", function()
  local symbols = get_symbols()
  local symbol = symbols.parse_line_for_symbol("invalid line format", 0)
  test_assert(symbol == nil, "should return nil for invalid format")

  local symbol2 = symbols.parse_line_for_symbol("2024-01-01 invalid directive", 0)
  test_assert(symbol2 == nil, "should return nil for invalid directive")
end)

-- Test 18: Parse selection ranges correctly
run_test("should set selection ranges correctly", function()
  local symbols = get_symbols()
  local symbol = symbols.parse_line_for_symbol("2024-01-01 open Assets:Checking USD", 0)

  test_assert(symbol ~= nil, "should return symbol")
  if symbol then
    test_assert(symbol.selectionRange ~= nil, "should have selection range")
    test_assert(symbol.selectionRange.start.line == 0, "should have correct selection start line")
    test_assert(symbol.selectionRange.start.character >= 0, "should have valid selection start character")
  end
end)

-- Test 19: Document symbols with mock buffer
run_test("should get document symbols from buffer", function()
  local symbols = get_symbols()

  -- Mock buffer functions

  ---@diagnostic disable-next-line: duplicate-set-field
  vim.api.nvim_get_current_buf = function()
    return 1
  end
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.api.nvim_buf_get_lines = function(_, _, _, _)
    return {
      '2024-01-01 * "Store" "Purchase"',
      "",
      "; Comment line",
      "2024-01-01 open Assets:Cash USD",
      'option "title" "Test Ledger"',
    }
  end

  local document_symbols = symbols.get_document_symbols()

  test_assert(type(document_symbols) == "table", "should return table of symbols")
  test_assert(#document_symbols == 3, "should find 3 symbols (transaction, open, option)")
  test_assert(document_symbols[1].name == "[2024-01-01] Store", "first symbol should be transaction")
  test_assert(document_symbols[2].name == "Assets:Cash", "second symbol should be account")
  test_assert(document_symbols[3].name == "title", "third symbol should be option")

  -- Restore original functions
  vim.api.nvim_get_current_buf = original_nvim_get_current_buf
  vim.api.nvim_buf_get_lines = original_nvim_buf_get_lines
end)

-- Test 20: Empty buffer handling
run_test("should handle empty buffer", function()
  local symbols = get_symbols()

  -- Mock empty buffer
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.api.nvim_get_current_buf = function()
    return 1
  end
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.api.nvim_buf_get_lines = function(_, _, _, _)
    return {}
  end

  local document_symbols = symbols.get_document_symbols()

  test_assert(type(document_symbols) == "table", "should return table for empty buffer")
  test_assert(#document_symbols == 0, "should find no symbols in empty buffer")

  -- Restore original functions
  vim.api.nvim_get_current_buf = original_nvim_get_current_buf
  vim.api.nvim_buf_get_lines = original_nvim_buf_get_lines
end)

-- Test 21: Complex transaction patterns
run_test("should handle complex transaction formats", function()
  local symbols = get_symbols()

  -- Transaction with complex payee/narration patterns
  local symbol1 = symbols.parse_line_for_symbol('2024-01-15 * "Store Name Inc." "Complex "quoted" description"', 0)
  test_assert(symbol1 ~= nil, "should parse transaction with complex quotes")
  if symbol1 then
    test_assert(symbol1.name == "[2024-01-15] Store Name Inc.", "should handle complex payee")
  end

  -- Transaction without quotes
  local symbol2 = symbols.parse_line_for_symbol("2024-01-15 * Payee Description", 0)
  test_assert(symbol2 ~= nil, "should parse transaction without quotes")
end)

-- Test 22: Symbol range accuracy
run_test("should set accurate symbol ranges", function()
  local symbols = get_symbols()
  local line = "2024-01-01 open Assets:Checking USD"
  local symbol = symbols.parse_line_for_symbol(line, 5)

  test_assert(symbol ~= nil, "should return symbol")
  if symbol then
    test_assert(symbol.range.start.line == 5, "should use provided line number")
    test_assert(symbol.range.start.character == 0, "should start at beginning of line")
    test_assert(symbol.range["end"].line == 5, "should end on same line")
    test_assert(symbol.range["end"].character == #line, "should end at line length")
  end
end)

-- Test 23: Account name patterns
run_test("should handle various account name patterns", function()
  local symbols = get_symbols()

  -- Account with numbers and underscores
  local symbol1 = symbols.parse_line_for_symbol("2024-01-01 open Assets:Account123 USD", 0)
  test_assert(symbol1 ~= nil, "should parse account with numbers")
  if symbol1 then
    test_assert(symbol1.name == "Assets:Account123", "should extract account name with numbers")
  end

  -- Account with simple names
  local symbol2 = symbols.parse_line_for_symbol("2024-01-01 close Liabilities:CreditCard", 0)
  test_assert(symbol2 ~= nil, "should parse account with mixed case")
  if symbol2 then
    test_assert(symbol2.name == "Liabilities:CreditCard", "should extract mixed case account name")
  end
end)

-- Test 24: Date format validation
run_test("should handle different date formats", function()
  local symbols = get_symbols()

  -- Valid ISO date
  local symbol1 = symbols.parse_line_for_symbol('2024-01-01 * "Valid date"', 0)
  test_assert(symbol1 ~= nil, "should parse valid ISO date")

  -- Invalid date format should not match
  local symbol2 = symbols.parse_line_for_symbol('24-01-01 * "Invalid date"', 0)
  test_assert(symbol2 == nil, "should not parse invalid date format")
end)

-- Test 25: Edge case - minimal transaction
run_test("should handle minimal transaction format", function()
  local symbols = get_symbols()
  local symbol = symbols.parse_line_for_symbol("2024-01-15 * ", 0)

  test_assert(symbol ~= nil, "should parse minimal transaction")
  if symbol then
    test_assert(symbol.name == "[2024-01-15] Transaction", "should use default name for minimal transaction")
    test_assert(symbol.detail:find("Completed"), "should indicate completed status")
  end
end)

-- Test 26: Pad directive parsing
run_test("should parse pad directive", function()
  local symbols = get_symbols()
  local symbol = symbols.parse_line_for_symbol("2024-01-01 pad Assets:Checking Equity:Opening-Balances", 0)

  test_assert(symbol ~= nil, "should return symbol for pad directive")
  if symbol then
    test_assert(symbol.name == "Assets:Checking <- Equity:Opening-Balances", "should format pad correctly")
    test_assert(symbol.detail == "Pad directive", "should have pad detail")
    test_assert(symbol.kind == 6, "should use Method symbol kind")
  end
end)

-- Test 27: Event directive parsing
run_test("should parse event directive", function()
  local symbols = get_symbols()
  local symbol = symbols.parse_line_for_symbol('2024-01-01 event "location" "New York"', 0)

  test_assert(symbol ~= nil, "should return symbol for event directive")
  if symbol then
    test_assert(symbol.name == "location", "should extract event type")
    test_assert(symbol.detail == "Event: New York", "should include event description")
    test_assert(symbol.kind == 24, "should use Event symbol kind")
  end
end)

-- Test 28: Event directive without description
run_test("should parse event directive without description", function()
  local symbols = get_symbols()
  local symbol = symbols.parse_line_for_symbol('2024-01-01 event "location"', 0)

  test_assert(symbol ~= nil, "should return symbol for event without description")
  if symbol then
    test_assert(symbol.name == "location", "should extract event type")
    test_assert(symbol.detail == "Event: ", "should have empty description")
  end
end)

-- Test 29: Account names with special characters (regression test)
run_test("should handle account names with hyphens safely", function()
  local symbols = get_symbols()
  local symbol = symbols.parse_line_for_symbol("2024-01-01 open Equity:Opening-Balances USD", 0)

  test_assert(symbol ~= nil, "should parse account with hyphens")
  if symbol then
    test_assert(symbol.name == "Equity:Opening-Balances", "should extract hyphenated account name")
    test_assert(symbol.selectionRange ~= nil, "should have selection range")
    test_assert(symbol.selectionRange.start.character >= 0, "should have valid selection range")
  end
end)

-- Test 30: Account closing with special characters (regression test)
run_test("should handle account closing with special characters", function()
  local symbols = get_symbols()
  local symbol = symbols.parse_line_for_symbol("2024-12-31 close Liabilities:Credit-Card", 0)

  test_assert(symbol ~= nil, "should parse account close with hyphens")
  if symbol then
    test_assert(symbol.name == "Liabilities:Credit-Card", "should extract hyphenated account name")
    test_assert(symbol.selectionRange ~= nil, "should have selection range")
    test_assert(symbol.selectionRange.start.character >= 0, "should have valid selection range")
  end
end)

-- Test 31: Complex transaction parsing (improved regex)
run_test("should handle complex transaction quotes correctly", function()
  local symbols = get_symbols()

  -- Test empty payee with quoted narration
  local symbol1 = symbols.parse_line_for_symbol('2024-01-15 * "" "Narration only"', 0)
  test_assert(symbol1 ~= nil, "should parse empty payee with narration")
  if symbol1 then
    test_assert(symbol1.name == "[2024-01-15] Narration only", "should use narration as name")
  end

  -- Test quoted payee without narration
  local symbol2 = symbols.parse_line_for_symbol('2024-01-15 * "Payee only"', 0)
  test_assert(symbol2 ~= nil, "should parse quoted payee only")
  if symbol2 then
    test_assert(symbol2.name == "[2024-01-15] Payee only", "should use payee as name")
  end
end)

-- Test 32: Option parsing with special characters
run_test("should handle option names and values with special characters", function()
  local symbols = get_symbols()
  local symbol = symbols.parse_line_for_symbol('option "operating_currency" "USD"', 0)

  test_assert(symbol ~= nil, "should parse option with underscores")
  if symbol then
    test_assert(symbol.name == "operating_currency", "should extract option name with underscores")
    test_assert(symbol.detail == "Option: USD", "should include option value")
    test_assert(symbol.selectionRange ~= nil, "should have selection range")
  end
end)

-- Test 33: Plugin parsing with complex names
run_test("should handle plugin names with dots and paths", function()
  local symbols = get_symbols()
  local symbol = symbols.parse_line_for_symbol('plugin "beancount.plugins.auto_accounts"', 0)

  test_assert(symbol ~= nil, "should parse plugin with complex name")
  if symbol then
    test_assert(symbol.name == "beancount.plugins.auto_accounts", "should extract full plugin name")
    test_assert(symbol.selectionRange ~= nil, "should have selection range")
    test_assert(symbol.selectionRange.start.character >= 0, "should have valid selection range")
  end
end)

-- Test 34: Include parsing with file paths
run_test("should handle include with file paths", function()
  local symbols = get_symbols()
  local symbol = symbols.parse_line_for_symbol('include "accounts/assets.bean"', 0)

  test_assert(symbol ~= nil, "should parse include with path")
  if symbol then
    test_assert(symbol.name == "accounts/assets.bean", "should extract file path")
    test_assert(symbol.selectionRange ~= nil, "should have selection range")
    test_assert(symbol.selectionRange.start.character >= 0, "should have valid selection range")
  end
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
