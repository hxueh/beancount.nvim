-- Beancount auto-fill module
-- Automatically fills missing amounts in incomplete transactions
-- Uses automatic posting data calculated by beancount library
local M = {}

local config = require("beancount.config")

-- Flag to prevent re-entry when triggering second save
local is_autofilling = false

-- Cache of automatic posting data from beancount validation
-- Structure: {filename: {line_number_str: ["amount string", ...]}}
M.automatics = {}

-- Cache of cost basis enhancement data from beancount
-- Structure: {filename: {line_number_str: "complete_position_string"}}
M.cost_basis_data = {}

-- Update automatic posting data from beancount validation
-- @param data_json string: JSON string containing automatic postings and cost basis data
M.update_data = function(data_json)
    if not data_json or data_json == "" then
        M.automatics = {}
        M.cost_basis_data = {}
        return
    end

    local ok, data = pcall(vim.json.decode, data_json)
    if ok and data then
        -- Handle new structure with both automatics and cost_basis
        if type(data) == "table" and (data.automatics or data.cost_basis) then
            M.automatics = data.automatics or {}
            M.cost_basis_data = data.cost_basis or {}
        else
            -- Backward compatibility: old format was just the automatics dict
            M.automatics = data
            M.cost_basis_data = {}
        end
    else
        M.automatics = {}
        M.cost_basis_data = {}
    end
end

-- Check if a line is a posting line without an amount
-- @param line_text string: Text of the line to check
-- @return boolean: True if line is a posting without amount
local function is_incomplete_posting(line_text)
    -- Pattern: whitespace + account name, but no amount
    -- Accounts start with capital letter and contain alphanumeric, colon, underscore, hyphen
    return line_text:match("^%s+[A-Z][a-zA-Z0-9:_-]+%s*$") ~= nil
end

-- Fill incomplete posting amounts in a buffer using automatic posting data
-- @param bufnr number: Buffer number to fill (defaults to current buffer)
-- @return boolean: True if any lines were modified
M.fill_incomplete_amounts = function(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    local filename = vim.api.nvim_buf_get_name(bufnr)

    -- Try to find the file automatics data
    -- Handle path variations (e.g., /private/var vs /var on macOS)
    local file_automatics = M.automatics[filename]
    if not file_automatics then
        -- Try resolving the realpath
        local ok, resolved = pcall(vim.loop.fs_realpath, filename)
        if ok and resolved then
            file_automatics = M.automatics[resolved]
        end

        -- Try checking all keys for a match
        if not file_automatics then
            for key, value in pairs(M.automatics) do
                local ok_key, resolved_key = pcall(vim.loop.fs_realpath, key)
                local ok_file, resolved_file = pcall(vim.loop.fs_realpath, filename)
                if ok_key and ok_file and resolved_key == resolved_file then
                    file_automatics = value
                    break
                end
            end
        end
    end

    if not file_automatics or vim.tbl_isempty(file_automatics) then
        return false
    end

    local lines_modified = 0

    -- Collect all line numbers and sort them in descending order
    -- This ensures we process from bottom to top, so line insertions don't affect
    -- the line numbers of entries we haven't processed yet
    local line_numbers = {}
    for line_str, _ in pairs(file_automatics) do
        local line_num = tonumber(line_str)
        if line_num then
            table.insert(line_numbers, line_num)
        end
    end
    table.sort(line_numbers, function(a, b)
        return a > b
    end)

    for _, line_num in ipairs(line_numbers) do
        local amounts = file_automatics[tostring(line_num)]

        -- Handle nil, old format (string), and new format (array) for backward compatibility
        if not amounts then
            amounts = {}
        elseif type(amounts) == "string" then
            amounts = { amounts }
        end

        if line_num > 0 and line_num <= vim.api.nvim_buf_line_count(bufnr) then
            -- Convert to 0-based indexing for nvim_buf_get_lines
            local zero_based_line = line_num - 1
            local line_text = vim.api.nvim_buf_get_lines(bufnr, zero_based_line, zero_based_line + 1, false)[1]

            if line_text and is_incomplete_posting(line_text) then
                -- Extract account name and indentation
                local indent, account = line_text:match("^(%s+)([A-Z][a-zA-Z0-9:_-]+)")

                if indent and account and #amounts > 0 then
                    -- Build new lines for all amounts
                    local new_lines = {}
                    for _, amount in ipairs(amounts) do
                        -- Use two spaces between account and amount for basic separation
                        table.insert(new_lines, indent .. account .. "  " .. amount)
                    end

                    -- Replace the original line with all new lines
                    vim.api.nvim_buf_set_lines(bufnr, zero_based_line, zero_based_line + 1, false, new_lines)
                    lines_modified = lines_modified + #new_lines
                end
            end
        end
    end

    return lines_modified > 0
end

-- Enhance cost basis notation in a buffer by adding dates and total cost
-- @param bufnr number: Buffer number to enhance (defaults to current buffer)
-- @return boolean: True if any lines were modified
M.enhance_cost_basis = function(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    local filename = vim.api.nvim_buf_get_name(bufnr)

    -- Try to find the file cost basis data
    -- Handle path variations (e.g., /private/var vs /var on macOS)
    local file_cost_basis = M.cost_basis_data[filename]
    if not file_cost_basis then
        -- Try resolving the realpath
        local ok, resolved = pcall(vim.loop.fs_realpath, filename)
        if ok and resolved then
            file_cost_basis = M.cost_basis_data[resolved]
        end

        -- Try checking all keys for a match
        if not file_cost_basis then
            for key, value in pairs(M.cost_basis_data) do
                local ok_key, resolved_key = pcall(vim.loop.fs_realpath, key)
                local ok_file, resolved_file = pcall(vim.loop.fs_realpath, filename)
                if ok_key and ok_file and resolved_key == resolved_file then
                    file_cost_basis = value
                    break
                end
            end
        end
    end

    if not file_cost_basis or vim.tbl_isempty(file_cost_basis) then
        return false
    end

    local lines_modified = 0

    -- Process each line that has cost basis data
    for line_str, enhanced_position in pairs(file_cost_basis) do
        -- Skip empty enhanced_position strings
        if not enhanced_position or enhanced_position == "" then
            goto continue
        end

        local line_num = tonumber(line_str)
        if line_num and line_num > 0 and line_num <= vim.api.nvim_buf_line_count(bufnr) then
            -- Convert to 0-based indexing for nvim_buf_get_lines
            local zero_based_line = line_num - 1
            local line_text = vim.api.nvim_buf_get_lines(bufnr, zero_based_line, zero_based_line + 1, false)[1]

            if line_text then
                -- Check if line has incomplete cost notation (has { but missing date or @@)
                local has_cost = line_text:match("{[^}]+}")
                if has_cost then
                    -- Check if already has both date and @@
                    local has_date = line_text:match("%d%d%d%d%-%d%d%-%d%d")
                    local has_total_cost = line_text:match("@@")

                    -- Only enhance if incomplete
                    if not (has_date and has_total_cost) then
                        -- Extract indent and account name from current line
                        local indent, account = line_text:match("^(%s+)([A-Z][a-zA-Z0-9:_%-]+)")

                        if indent and account then
                            -- Build new line with enhanced position
                            local new_line = indent .. account .. "  " .. enhanced_position
                            vim.api.nvim_buf_set_lines(bufnr, zero_based_line, zero_based_line + 1, false, { new_line })
                            lines_modified = lines_modified + 1
                        end
                    end
                end
            end
        end

        ::continue::
    end

    return lines_modified > 0
end

-- Fill missing amounts in a buffer using automatic posting data and enhance cost basis
-- @param bufnr number: Buffer number to fill (defaults to current buffer)
-- @return boolean: True if any lines were modified
M.fill_buffer = function(bufnr)
    if not config.get("auto_fill_amounts") then
        return false
    end

    bufnr = bufnr or vim.api.nvim_get_current_buf()

    -- Run synchronous validation to get fresh data
    -- This ensures newly added transactions are detected on first save
    local diagnostics = require("beancount.diagnostics")
    local fresh_data = diagnostics.check_file_sync()
    if fresh_data then
        -- Update both automatics and cost_basis data
        M.update_data(vim.json.encode(fresh_data))
    end

    -- Save cursor position to restore after filling
    local cursor_pos = vim.api.nvim_win_get_cursor(0)
    local total_modified = false

    -- Phase 1: Fill incomplete amounts
    local amounts_modified = M.fill_incomplete_amounts(bufnr)
    total_modified = total_modified or amounts_modified

    -- Phase 2: Enhance cost basis
    local cost_basis_modified = M.enhance_cost_basis(bufnr)
    total_modified = total_modified or cost_basis_modified

    -- Restore cursor position
    pcall(vim.api.nvim_win_set_cursor, 0, cursor_pos)

    -- If lines were modified and formatter is enabled, run it to align amounts
    if total_modified and config.get("auto_format_on_save") then
        local formatter = require("beancount.formatter")
        formatter.format_buffer()
    end

    return total_modified
end

-- Initialize autofill for a specific buffer
-- Sets up BufWritePost autocmd to fill amounts after saving
-- @param bufnr number: Buffer number to setup (defaults to current buffer)
M.setup_buffer = function(bufnr)
    if not config.get("auto_fill_amounts") then
        return
    end

    bufnr = bufnr or vim.api.nvim_get_current_buf()

    local augroup = vim.api.nvim_create_augroup("BeancountAutofill_" .. bufnr, { clear = true })

    -- Fill amounts after saving (beancheck reads fresh file from disk)
    vim.api.nvim_create_autocmd("BufWritePost", {
        group = augroup,
        buffer = bufnr,
        callback = function()
            -- Prevent re-entry when we trigger second save
            if is_autofilling then
                return
            end

            is_autofilling = true
            local ok, modified = pcall(M.fill_buffer, bufnr)
            -- Save again if autofill made changes
            if ok and modified then
                vim.cmd("silent write")
            end
            is_autofilling = false
        end,
    })
end

-- Initialize the autofill module globally
M.setup = function()
    -- No global initialization needed currently
    -- All setup is done per-buffer
end

return M
