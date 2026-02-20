-- Comprehensive test for autofill module
-- Tests both unit functionality and end-to-end integration
-- Run with: nvim --headless --noplugin -c "luafile tests/autofill_test.lua"

-- Add lua path to find beancount modules
---@diagnostic disable-next-line: redundant-parameter
vim.opt.runtimepath:prepend(vim.fn.getcwd())

print("Running autofill module tests...")

-- Test counter
local tests_run = 0
local tests_passed = 0

-- Track files to cleanup
local files_to_cleanup = {}

local function test_assert(condition, message)
    if not condition then
        error("Test failed: " .. (message or "assertion failed"))
    end
end

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

-- Cleanup function that always runs
local function cleanup_files()
    for _, file in ipairs(files_to_cleanup) do
        if vim.fn.filereadable(file) == 1 then
            vim.fn.delete(file)
        end
    end
    files_to_cleanup = {}
end

-- Mock vim.diagnostic.config to avoid errors
vim.diagnostic = vim.diagnostic or {}
vim.diagnostic.config = function() end

local autofill = require("beancount.autofill")
local config = require("beancount.config")

print("\n--- Unit Tests ---")

-- Test 1: Module loads correctly
run_test("should load autofill module correctly", function()
    test_assert(autofill ~= nil, "Autofill module should load")
    test_assert(type(autofill.setup) == "function", "setup() should exist")
    test_assert(type(autofill.setup_buffer) == "function", "setup_buffer() should exist")
    test_assert(type(autofill.update_data) == "function", "update_data() should exist")
    test_assert(type(autofill.fill_buffer) == "function", "fill_buffer() should exist")
end)

-- Test 2: update_data() parses JSON correctly (new array format)
run_test("should parse JSON data correctly", function()
    local test_json = vim.json.encode({
        ["/test/file.beancount"] = {
            ["10"] = { "-20002.00 USD" },
            ["15"] = { "-50.00 USD" }
        }
    })
    autofill.update_data(test_json)
    test_assert(autofill.automatics["/test/file.beancount"] ~= nil, "Should parse file data")
    test_assert(autofill.automatics["/test/file.beancount"]["10"][1] == "-20002.00 USD", "Should parse line 10")
    test_assert(autofill.automatics["/test/file.beancount"]["15"][1] == "-50.00 USD", "Should parse line 15")
end)

-- Test 3: update_data() handles empty input
run_test("should handle empty input correctly", function()
    autofill.update_data("")
    test_assert(vim.tbl_isempty(autofill.automatics), "Should clear data on empty input")
    autofill.update_data(nil)
    test_assert(vim.tbl_isempty(autofill.automatics), "Should clear data on nil input")
end)

-- Test 4: Configuration integration
run_test("should integrate with config correctly", function()
    config.setup({ auto_fill_amounts = false })
    test_assert(config.get("auto_fill_amounts") == false, "Should be disabled by default")
    config.set("auto_fill_amounts", true)
    test_assert(config.get("auto_fill_amounts") == true, "Should be able to enable")
    config.set("auto_fill_amounts", false) -- Reset for other tests
end)

-- Test 5: Buffer setup doesn't crash when feature is disabled
run_test("should skip setup when feature is disabled", function()
    config.set("auto_fill_amounts", false)
    local buf = vim.api.nvim_create_buf(false, true)
    autofill.setup_buffer(buf)
    -- Should return early without setting up autocmds
    -- pcall because the augroup might not exist at all (which is what we want)
    local ok, augroups = pcall(vim.api.nvim_get_autocmds, { group = "BeancountAutofill_" .. buf })
    test_assert(not ok or #augroups == 0, "Should not create autocmds when disabled")
    vim.api.nvim_buf_delete(buf, { force = true })
end)

-- Test 6: fill_buffer() with test data (single currency)
run_test("should fill incomplete postings correctly", function()
    config.set("auto_fill_amounts", true)
    config.set("auto_format_on_save", false) -- Disable formatter for this test

    -- Create a test buffer with incomplete transaction
    local test_buf = vim.api.nvim_create_buf(false, true)
    local test_file = vim.fn.tempname() .. ".beancount"
    vim.api.nvim_buf_set_name(test_buf, test_file)
    vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, {
        "2025-10-10 * \"Test\" \"Transaction\"",
        "  Assets:Stock                      100.00 AAPL",
        "  Expenses:Trading                  2.00 USD",
        "  Assets:Cash"
    })

    -- Get the actual buffer name (might be normalized)
    local actual_filename = vim.api.nvim_buf_get_name(test_buf)

    -- Set up automatic posting data for this file using the actual filename (new array format)
    local fill_data = vim.json.encode({
        [actual_filename] = {
            ["4"] = { "-20002.00 USD" }
        }
    })
    autofill.update_data(fill_data)

    -- Verify data was loaded
    test_assert(autofill.automatics[actual_filename] ~= nil, "Should have data for test file")
    test_assert(autofill.automatics[actual_filename]["4"] ~= nil, "Should have data for line 4")

    -- Run fill_buffer
    autofill.fill_buffer(test_buf)

    -- Check if the line was filled
    local lines = vim.api.nvim_buf_get_lines(test_buf, 0, -1, false)
    test_assert(lines[4]:match("%-20002%.00 USD") ~= nil, "Should fill missing amount")

    -- Cleanup
    vim.api.nvim_buf_delete(test_buf, { force = true })
    config.set("auto_fill_amounts", false)
end)

-- Test 6a: fill_buffer() with multi-currency data
run_test("should fill incomplete postings with multiple currencies", function()
    config.set("auto_fill_amounts", true)
    config.set("auto_format_on_save", false) -- Disable formatter for this test

    -- Create a test buffer with multi-currency transaction
    local test_buf = vim.api.nvim_create_buf(false, true)
    local test_file = vim.fn.tempname() .. ".beancount"
    vim.api.nvim_buf_set_name(test_buf, test_file)
    vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, {
        "2025-10-10 * \"Bank\" \"Interest\"",
        "  Income:Interest                  -100.00 USD",
        "  Income:Interest                  -50.00 GBP",
        "  Assets:Bank"
    })

    -- Get the actual buffer name (might be normalized)
    local actual_filename = vim.api.nvim_buf_get_name(test_buf)

    -- Set up automatic posting data with multiple currencies for line 4
    local fill_data = vim.json.encode({
        [actual_filename] = {
            ["4"] = { "100.00 USD", "50.00 GBP" }
        }
    })
    autofill.update_data(fill_data)

    -- Verify data was loaded
    test_assert(autofill.automatics[actual_filename] ~= nil, "Should have data for test file")
    test_assert(#autofill.automatics[actual_filename]["4"] == 2, "Should have 2 amounts for line 4")

    -- Run fill_buffer
    autofill.fill_buffer(test_buf)

    -- Check if the line was expanded to multiple lines
    local lines = vim.api.nvim_buf_get_lines(test_buf, 0, -1, false)
    test_assert(#lines == 5, "Should have 5 lines after expansion (was 4, added 1)")
    test_assert(lines[4]:match("Assets:Bank.*100%.00 USD") ~= nil, "Line 4 should have USD amount")
    test_assert(lines[5]:match("Assets:Bank.*50%.00 GBP") ~= nil, "Line 5 should have GBP amount")

    -- Cleanup
    vim.api.nvim_buf_delete(test_buf, { force = true })
    config.set("auto_fill_amounts", false)
end)

-- Test 6.5: Inlay hints should be disabled when autofill is enabled
run_test("should disable inlay hints when autofill is enabled", function()
    local inlay_hints = require("beancount.inlay_hints")

    -- Enable autofill
    config.set("auto_fill_amounts", true)
    config.set("inlay_hints", true)

    -- Create a test buffer
    local test_buf = vim.api.nvim_create_buf(false, true)
    local test_file = vim.fn.tempname() .. ".beancount"
    vim.api.nvim_buf_set_name(test_buf, test_file)

    -- Set up automatic posting data (new array format)
    local actual_filename = vim.api.nvim_buf_get_name(test_buf)
    local hints_data = vim.json.encode({
        [actual_filename] = {
            ["4"] = { "-100.00 USD" }
        }
    })
    inlay_hints.update_data(hints_data)

    -- Try to render hints - should be skipped due to auto_fill_amounts
    inlay_hints.render_hints(test_buf)

    -- Check that no extmarks were created (hints were not rendered)
    local extmarks = vim.api.nvim_buf_get_extmarks(test_buf, inlay_hints.namespace, 0, -1, {})
    test_assert(#extmarks == 0, "Should not render hints when auto_fill_amounts is enabled")

    -- Cleanup
    vim.api.nvim_buf_delete(test_buf, { force = true })
    config.set("auto_fill_amounts", false)
end)

-- Test 7: Re-entry guard prevents infinite loop
run_test("should prevent re-entry during autofill", function()
    config.set("auto_fill_amounts", true)
    config.set("auto_format_on_save", false)

    -- Create a test file first
    local test_file = vim.fn.tempname() .. ".beancount"
    table.insert(files_to_cleanup, test_file)
    local content = {
        "2025-10-10 * \"Test\" \"Transaction\"",
        "  Assets:Bank                      100.00 USD",
        "  Expenses:Test"
    }
    vim.fn.writefile(content, test_file)

    -- Open the file in a real buffer (not scratch)
    vim.cmd("edit " .. vim.fn.fnameescape(test_file))
    local test_buf = vim.api.nvim_get_current_buf()

    -- Mock the diagnostics.check_file_sync to avoid needing python
    local diagnostics = require("beancount.diagnostics")
    local original_check_file_sync = diagnostics.check_file_sync
    local actual_filename = vim.api.nvim_buf_get_name(test_buf)
    diagnostics.check_file_sync = function()
        return {
            [actual_filename] = {
                ["3"] = { "-100.00 USD" }
            }
        }
    end

    -- Setup autofill for buffer (this registers the BufWritePost autocmd)
    autofill.setup_buffer(test_buf)

    -- Track how many times fill_buffer is called
    local fill_count = 0
    local original_fill = autofill.fill_buffer
    autofill.fill_buffer = function(bufnr)
        fill_count = fill_count + 1
        -- Prevent actual infinite loop by limiting calls
        if fill_count > 5 then
            error("Infinite loop detected! fill_buffer called too many times")
        end
        return original_fill(bufnr)
    end

    -- Trigger save which should call fill_buffer once, then save again
    -- The re-entry guard should prevent the second save from triggering fill_buffer again
    vim.cmd("silent write")

    -- Restore original functions
    autofill.fill_buffer = original_fill
    diagnostics.check_file_sync = original_check_file_sync

    -- fill_buffer should be called exactly once (the guard prevents second call)
    test_assert(fill_count == 1, "fill_buffer should be called exactly once, got " .. fill_count)

    -- Cleanup
    vim.cmd("bdelete!")
    config.set("auto_fill_amounts", false)
end)

print("\n--- Integration Tests ---")

-- Test 7: End-to-end integration with real beancount file
run_test("should auto-fill on save (end-to-end)", function()
    -- Copy the test file to a temporary location
    local source_file = "tests/example/test_autofill.beancount"
    local test_file = vim.fn.tempname() .. ".beancount"
    table.insert(files_to_cleanup, test_file)

    -- Read source and write to temp file
    local source_content = vim.fn.readfile(source_file)
    vim.fn.writefile(source_content, test_file)

    -- Determine Python path (check for venv first, fallback to system python)
    local python_path = "python3"
    if vim.fn.executable(".venv/bin/python") == 1 then
        python_path = ".venv/bin/python"
    elseif vim.fn.executable("python") == 1 then
        python_path = "python"
    end

    -- Verify beancount is installed
    local check_beancount = vim.fn.system(python_path .. " -c 'import beancount' 2>&1")
    if vim.v.shell_error ~= 0 then
        print("  ⚠ Skipping integration test: beancount not installed for " .. python_path)
        tests_run = tests_run - 1  -- Don't count this as a failed test
        return
    end

    -- Setup the plugin
    local beancount = require("beancount")
    beancount.setup({
        auto_fill_amounts = true,
        auto_format_on_save = false,
        python_path = python_path
    })

    -- Open the file in a buffer
    vim.cmd("edit " .. vim.fn.fnameescape(test_file))
    local bufnr = vim.api.nvim_get_current_buf()

    -- Wait for initial diagnostics to complete
    local diagnostics_ready = vim.wait(2000, function()
        local diagnostics = require("beancount.diagnostics")
        return diagnostics.get_hints_data() ~= nil and diagnostics.get_hints_data() ~= ""
    end, 100)

    test_assert(diagnostics_ready, "Diagnostics should complete within timeout")

    -- Get lines before save
    local lines_before = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local has_incomplete_before = false
    for _, line in ipairs(lines_before) do
        if line:match("^%s+Assets:Cash%s*$") then
            has_incomplete_before = true
            break
        end
    end
    test_assert(has_incomplete_before, "Should have incomplete posting before save")

    -- Save the buffer (this should trigger autofill)
    vim.cmd("write")
    vim.wait(500) -- Wait for async operations

    -- Get lines after save
    local lines_after = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    -- Check if amounts were filled
    local filled_count = 0
    for _, line in ipairs(lines_after) do
        if line:match("Assets:Cash.*%-20002%.00 USD") or line:match("Assets:Cash.*%-50%.00 USD") then
            filled_count = filled_count + 1
        end
    end

    test_assert(filled_count >= 1, "Should fill at least one missing amount")

    -- Verify file was saved with changes
    local saved_content = vim.fn.readfile(test_file)
    local saved_filled = false
    for _, line in ipairs(saved_content) do
        if line:match("Assets:Cash.*USD") then
            saved_filled = true
            break
        end
    end
    test_assert(saved_filled, "Changes should be saved to file")

    -- Cleanup buffer
    vim.cmd("bdelete!")
end)

print("\n--- Cost Basis Enhancement Tests ---")

-- Test 8: update_data() should parse new JSON structure with cost_basis field
run_test("should parse new JSON structure with cost_basis field", function()
    local test_data = {
        automatics = {
            ["/test/file.beancount"] = {
                ["10"] = { "-100.00 USD" }
            }
        },
        cost_basis = {
            ["/test/file.beancount"] = {
                ["5"] = "100.00 AAPL {150.00 USD, 2025-10-12} @@ 15000.0000 USD"
            }
        }
    }
    local test_json = vim.json.encode(test_data)

    autofill.update_data(test_json)

    test_assert(autofill.automatics["/test/file.beancount"] ~= nil, "Should parse automatics")
    test_assert(autofill.automatics["/test/file.beancount"]["10"][1] == "-100.00 USD", "Should parse automatics data")
    test_assert(autofill.cost_basis_data["/test/file.beancount"] ~= nil, "Should parse cost_basis")
    local expected_cost = "100.00 AAPL {150.00 USD, 2025-10-12} @@ 15000.0000 USD"
    test_assert(autofill.cost_basis_data["/test/file.beancount"]["5"] == expected_cost, "Should parse cost_basis data")
end)

-- Test 9: update_data() should handle backward compatibility with old format
run_test("should handle backward compatibility with old JSON format", function()
    local old_format_data = {
        ["/test/file.beancount"] = {
            ["10"] = { "-100.00 USD" }
        }
    }
    local test_json = vim.json.encode(old_format_data)

    autofill.update_data(test_json)

    test_assert(autofill.automatics["/test/file.beancount"] ~= nil, "Should parse old format automatics")
    test_assert(autofill.automatics["/test/file.beancount"]["10"][1] == "-100.00 USD", "Should parse old format data")
    test_assert(vim.tbl_isempty(autofill.cost_basis_data), "Should have empty cost_basis for old format")
end)

-- Test 10: enhance_cost_basis() should enhance incomplete postings
run_test("should enhance incomplete cost basis postings", function()
    config.set("auto_fill_amounts", true)

    -- Create a test buffer with incomplete cost basis
    local test_buf = vim.api.nvim_create_buf(false, true)
    local test_file = vim.fn.tempname() .. ".beancount"
    vim.api.nvim_buf_set_name(test_buf, test_file)
    vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, {
        "2025-10-12 * \"AAPL\" \"Stock Purchase\"",
        "  Assets:Stock                      100.00 AAPL {150.00 USD}",
        "  Assets:Cash                       -15000.00 USD"
    })

    -- Get the actual buffer name
    local actual_filename = vim.api.nvim_buf_get_name(test_buf)

    -- Set up cost basis data for this file
    local cost_data = {
        cost_basis = {
            [actual_filename] = {
                ["2"] = "100.00 AAPL {150.00 USD, 2025-10-12} @@ 15000.0000 USD"
            }
        }
    }
    autofill.update_data(vim.json.encode(cost_data))

    -- Verify data was loaded
    test_assert(autofill.cost_basis_data[actual_filename] ~= nil, "Should have cost_basis data for test file")
    test_assert(autofill.cost_basis_data[actual_filename]["2"] ~= nil, "Should have data for line 2")

    -- Run enhance_cost_basis
    local modified = autofill.enhance_cost_basis(test_buf)

    test_assert(modified == true, "Should report modifications")

    -- Check if the line was enhanced
    local lines = vim.api.nvim_buf_get_lines(test_buf, 0, -1, false)
    test_assert(lines[2]:match("{150.00 USD, 2025%-10%-12}") ~= nil, "Should add date to cost")
    test_assert(lines[2]:match("@@ 15000.0000 USD") ~= nil, "Should add total cost notation")

    -- Cleanup
    vim.api.nvim_buf_delete(test_buf, { force = true })
    config.set("auto_fill_amounts", false)
end)

-- Test 11: enhance_cost_basis() should skip already complete postings
run_test("should skip already complete cost basis postings", function()
    config.set("auto_fill_amounts", true)

    -- Create a test buffer with complete cost basis
    local test_buf = vim.api.nvim_create_buf(false, true)
    local test_file = vim.fn.tempname() .. ".beancount"
    vim.api.nvim_buf_set_name(test_buf, test_file)
    local complete_line = "  Assets:Stock                      100.00 AAPL {150.00 USD, 2025-10-12} @@ 15000.0000 USD"
    vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, {
        "2025-10-12 * \"AAPL\" \"Stock Purchase\"",
        complete_line,
        "  Assets:Cash                       -15000.00 USD"
    })

    -- Get the actual buffer name
    local actual_filename = vim.api.nvim_buf_get_name(test_buf)

    -- Set up cost basis data (even though line is complete)
    local cost_data = {
        cost_basis = {
            [actual_filename] = {
                ["2"] = "100.00 AAPL {150.00 USD, 2025-10-12} @@ 15000.0000 USD"
            }
        }
    }
    autofill.update_data(vim.json.encode(cost_data))

    -- Run enhance_cost_basis
    local modified = autofill.enhance_cost_basis(test_buf)

    test_assert(modified == false, "Should NOT report modifications for complete line")

    -- Check that line was NOT modified
    local lines = vim.api.nvim_buf_get_lines(test_buf, 0, -1, false)
    test_assert(lines[2] == complete_line, "Line should remain unchanged")

    -- Cleanup
    vim.api.nvim_buf_delete(test_buf, { force = true })
    config.set("auto_fill_amounts", false)
end)

print("\n--- Edge Case Tests ---")

-- Test 12: Cost with date but no @@ (should add @@)
run_test("should add @@ when cost has date but no total", function()
    config.set("auto_fill_amounts", true)

    local test_buf = vim.api.nvim_create_buf(false, true)
    local test_file = vim.fn.tempname() .. ".beancount"
    vim.api.nvim_buf_set_name(test_buf, test_file)
    vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, {
        "2025-10-14 * \"AAPL\" \"Stock Purchase with Date\"",
        "  Assets:Stock                      25.00 AAPL {200.00 USD, 2025-10-14}",
        "  Assets:Cash                       -5000.00 USD"
    })

    local actual_filename = vim.api.nvim_buf_get_name(test_buf)

    -- Cost basis data should add @@ notation even when date exists
    local cost_data = {
        cost_basis = {
            [actual_filename] = {
                ["2"] = "25.00 AAPL {200.00 USD, 2025-10-14} @@ 5000.00 USD"
            }
        }
    }
    autofill.update_data(vim.json.encode(cost_data))

    local modified = autofill.enhance_cost_basis(test_buf)

    test_assert(modified == true, "Should report modifications")

    local lines = vim.api.nvim_buf_get_lines(test_buf, 0, -1, false)
    test_assert(lines[2]:match("@@ 5000%.00 USD") ~= nil, "Should add total cost notation")

    vim.api.nvim_buf_delete(test_buf, { force = true })
    config.set("auto_fill_amounts", false)
end)

-- Test 13: Handle deeply nested account names
run_test("should handle deeply nested account names", function()
    config.set("auto_fill_amounts", true)

    local test_buf = vim.api.nvim_create_buf(false, true)
    local test_file = vim.fn.tempname() .. ".beancount"
    vim.api.nvim_buf_set_name(test_buf, test_file)
    vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, {
        "2025-10-19 * \"AAPL\" \"Deep nested account\"",
        "  Assets:US:Broker:IRA:Stocks:Tech  10.00 AAPL {200.00 USD}",
        "  Assets:Cash                       -2000.00 USD"
    })

    local actual_filename = vim.api.nvim_buf_get_name(test_buf)

    local cost_data = {
        cost_basis = {
            [actual_filename] = {
                ["2"] = "10.00 AAPL {200.00 USD, 2025-10-19} @@ 2000.00 USD"
            }
        }
    }
    autofill.update_data(vim.json.encode(cost_data))

    local modified = autofill.enhance_cost_basis(test_buf)

    test_assert(modified == true, "Should report modifications for nested account")

    local lines = vim.api.nvim_buf_get_lines(test_buf, 0, -1, false)
    test_assert(lines[2]:match("Assets:US:Broker:IRA:Stocks:Tech") ~= nil, "Should preserve account name")
    test_assert(lines[2]:match("{200.00 USD, 2025%-10%-19}") ~= nil, "Should add date")
    test_assert(lines[2]:match("@@ 2000%.00 USD") ~= nil, "Should add total cost")

    vim.api.nvim_buf_delete(test_buf, { force = true })
    config.set("auto_fill_amounts", false)
end)

-- Test 14: Handle empty enhanced_position string gracefully
run_test("should handle empty enhanced_position gracefully", function()
    config.set("auto_fill_amounts", true)

    local test_buf = vim.api.nvim_create_buf(false, true)
    local test_file = vim.fn.tempname() .. ".beancount"
    vim.api.nvim_buf_set_name(test_buf, test_file)
    local original_line = "  Assets:Stock                      100.00 AAPL {150.00 USD}"
    vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, {
        "2025-10-12 * \"AAPL\" \"Test\"",
        original_line,
        "  Assets:Cash                       -15000.00 USD"
    })

    local actual_filename = vim.api.nvim_buf_get_name(test_buf)

    -- Set up cost basis data with empty string
    local cost_data = {
        cost_basis = {
            [actual_filename] = {
                ["2"] = ""
            }
        }
    }
    autofill.update_data(vim.json.encode(cost_data))

    -- Should not crash
    local modified = autofill.enhance_cost_basis(test_buf)

    -- Should not modify the line with empty data
    test_assert(modified == false, "Should not modify with empty enhanced_position")

    local lines = vim.api.nvim_buf_get_lines(test_buf, 0, -1, false)
    test_assert(lines[2] == original_line, "Line should remain unchanged")

    vim.api.nvim_buf_delete(test_buf, { force = true })
    config.set("auto_fill_amounts", false)
end)

-- Test 15: Handle line numbers beyond buffer length
run_test("should handle line numbers beyond buffer length", function()
    config.set("auto_fill_amounts", true)

    local test_buf = vim.api.nvim_create_buf(false, true)
    local test_file = vim.fn.tempname() .. ".beancount"
    vim.api.nvim_buf_set_name(test_buf, test_file)
    vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, {
        "2025-10-12 * \"Test\"",
        "  Assets:Cash                       100.00 USD"
    })

    local actual_filename = vim.api.nvim_buf_get_name(test_buf)

    -- Set up cost basis data for line 1000 (beyond buffer)
    local cost_data = {
        cost_basis = {
            [actual_filename] = {
                ["1000"] = "100.00 AAPL {150.00 USD, 2025-10-12} @@ 15000.00 USD"
            }
        }
    }
    autofill.update_data(vim.json.encode(cost_data))

    -- Should not crash
    local modified = autofill.enhance_cost_basis(test_buf)

    test_assert(modified == false, "Should not modify when line beyond buffer")

    vim.api.nvim_buf_delete(test_buf, { force = true })
    config.set("auto_fill_amounts", false)
end)

-- Test 16: Return false when file not in cost_basis_data
run_test("should return false when file not in cost_basis_data", function()
    config.set("auto_fill_amounts", true)

    -- Clear cost_basis_data completely - no data for any file
    autofill.update_data("")

    local test_buf = vim.api.nvim_create_buf(false, true)
    local test_file = vim.fn.tempname() .. ".beancount"
    vim.api.nvim_buf_set_name(test_buf, test_file)
    vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, {
        "2025-10-12 * \"Test\"",
        "  Assets:Stock                      100.00 AAPL {150.00 USD}",
        "  Assets:Cash                       -15000.00 USD"
    })

    -- cost_basis_data is now empty ({}), so this file won't be found
    local modified = autofill.enhance_cost_basis(test_buf)

    test_assert(modified == false, "Should return false when cost_basis_data is empty")

    vim.api.nvim_buf_delete(test_buf, { force = true })
    config.set("auto_fill_amounts", false)
end)

-- Test 17: Handle mixed cost states in same transaction
run_test("should handle mixed cost states in same transaction", function()
    config.set("auto_fill_amounts", true)

    local test_buf = vim.api.nvim_create_buf(false, true)
    local test_file = vim.fn.tempname() .. ".beancount"
    vim.api.nvim_buf_set_name(test_buf, test_file)
    local complete_line = "  Assets:Stock                      50.00 AAPL {180.00 USD, 2025-10-15} @@ 9000.00 USD"
    vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, {
        "2025-10-15 * \"AAPL\" \"Mixed cost states\"",
        "  Assets:Stock                      100.00 AAPL {150.00 USD}",
        complete_line,
        "  Assets:Cash                       -24000.00 USD"
    })

    local actual_filename = vim.api.nvim_buf_get_name(test_buf)

    -- Only line 2 should be enhanced, line 3 is already complete
    local cost_data = {
        cost_basis = {
            [actual_filename] = {
                ["2"] = "100.00 AAPL {150.00 USD, 2025-10-15} @@ 15000.00 USD",
                ["3"] = "50.00 AAPL {180.00 USD, 2025-10-15} @@ 9000.00 USD"
            }
        }
    }
    autofill.update_data(vim.json.encode(cost_data))

    local modified = autofill.enhance_cost_basis(test_buf)

    test_assert(modified == true, "Should report modifications for incomplete posting")

    local lines = vim.api.nvim_buf_get_lines(test_buf, 0, -1, false)
    -- Line 2 should be enhanced
    test_assert(lines[2]:match("{150.00 USD, 2025%-10%-15}") ~= nil, "Should add date to incomplete line")
    test_assert(lines[2]:match("@@ 15000%.00 USD") ~= nil, "Should add @@ to incomplete line")
    -- Line 3 should remain unchanged
    test_assert(lines[3] == complete_line, "Complete line should remain unchanged")

    vim.api.nvim_buf_delete(test_buf, { force = true })
    config.set("auto_fill_amounts", false)
end)

-- Test 18: High precision cost (preserves 3 decimal places)
run_test("should preserve high precision in cost basis", function()
    config.set("auto_fill_amounts", true)

    local test_buf = vim.api.nvim_create_buf(false, true)
    local test_file = vim.fn.tempname() .. ".beancount"
    vim.api.nvim_buf_set_name(test_buf, test_file)
    vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, {
        "2025-10-16 * \"SGOV\" \"High precision cost\"",
        "  Assets:Stock                      65.00 SGOV {100.438 USD}",
        "  Assets:Cash                       -6528.47 USD"
    })

    local actual_filename = vim.api.nvim_buf_get_name(test_buf)

    -- The enhanced position should preserve 100.438 (not round to 100.44)
    local cost_data = {
        cost_basis = {
            [actual_filename] = {
                ["2"] = "65.00 SGOV {100.438 USD, 2025-10-16} @@ 6528.47 USD"
            }
        }
    }
    autofill.update_data(vim.json.encode(cost_data))

    local modified = autofill.enhance_cost_basis(test_buf)

    test_assert(modified == true, "Should report modifications")

    local lines = vim.api.nvim_buf_get_lines(test_buf, 0, -1, false)
    -- Should preserve 100.438 precision
    test_assert(lines[2]:match("{100.438 USD, 2025%-10%-16}") ~= nil, "Should preserve 3-decimal precision")
    test_assert(lines[2]:match("@@ 6528%.47 USD") ~= nil, "Should have correct total cost")

    vim.api.nvim_buf_delete(test_buf, { force = true })
    config.set("auto_fill_amounts", false)
end)

-- Summary
print("\n" .. string.rep("=", 50))
print(string.format("Tests: %d/%d passed", tests_passed, tests_run))

-- Always cleanup files
cleanup_files()

if tests_passed == tests_run then
    print("All tests passed! ✓")
    print(string.rep("=", 50))
    vim.cmd("qa!")
else
    print(string.format("Failed: %d", tests_run - tests_passed))
    print(string.rep("=", 50))
    vim.cmd("cq") -- Exit with error code
end
