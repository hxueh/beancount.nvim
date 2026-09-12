-- Load exploration data only on request so routine completion stays compact.
local M = { requests = {} }
local utils = require("beancount.utils")
local config = require("beancount.config")
local syntax = require("beancount.syntax")

local function notify(message)
    vim.notify("Beancount: " .. message, vim.log.levels.WARN)
end

function M.request(payload, callback)
    local root = utils.get_main_bean_file()
    if root == "" or not utils.file_exists(root) then notify("Ledger root unavailable"); return end
    root = vim.loop.fs_realpath(root) or root
    local snapshots, ticks = vim.empty_dict(), {}
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == "beancount" then
            local path = vim.api.nvim_buf_get_name(buf)
            if path ~= "" then
                snapshots[path] = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n") .. "\n"
                ticks[buf] = vim.api.nvim_buf_get_changedtick(buf)
            end
        end
    end
    payload.root, payload.snapshots = root, snapshots
    local previous = M.requests[root]
    if previous and previous.job and previous.job > 0 then vim.fn.jobstop(previous.job) end
    local request = {}
    M.requests[root] = request
    request.job = utils.run_cmd(utils.get_python_path(), { utils.get_plugin_dir() .. "/pythonFiles/editor.py" },
        function(stdout, stderr, code)
            if M.requests[root] ~= request then return end
            M.requests[root] = nil
            if code ~= 0 then notify(stderr); return end
            -- Never offer jumps or balances for source locations changed during loading.
            for buf, tick in pairs(ticks) do
                if not vim.api.nvim_buf_is_valid(buf) or vim.api.nvim_buf_get_changedtick(buf) ~= tick then
                    notify("Buffers changed while loading; run the command again")
                    return
                end
            end
            local ok, result = pcall(vim.json.decode, stdout)
            if not ok or type(result) ~= "table" then notify("Invalid exploration response"); return end
            callback(result)
        end, { stdin = vim.json.encode(payload), timeout_ms = config.get("validation_timeout_ms") })
end

-- Mask strings and comments without shifting byte columns, including UTF-8 accounts.
function M.token_at(line, col)
    local clean, quoted, escaped = {}, false, false
    for i = 1, #line do
        local char = line:sub(i, i)
        if escaped then clean[i], escaped = " ", false
        elseif quoted and char == "\\" then clean[i], escaped = " ", true
        elseif char == '"' then quoted, clean[i] = not quoted, " "
        elseif not quoted and char == ";" then break
        else clean[i] = quoted and " " or char end
    end
    line = table.concat(clean)
    for start, token, finish in line:gmatch("()([#%^][%w_./%-]+)()") do
        if col >= start and col < finish then return token end
    end
    return syntax.account_at(line, col)
end

function M.references(token)
    token = token or M.token_at(vim.fn.getline("."), vim.fn.col("."))
    if not token then notify("Place the cursor on an account, tag, or link"); return end
    M.request({ action = "references", token = token }, function(result)
        vim.fn.setqflist({}, " ", { title = "Beancount references: " .. token, items = result.items })
        if #result.items > 0 then vim.cmd("copen") else notify("No references found") end
        if result.warnings and #result.warnings > 0 then notify("Results are partial: ledger has errors") end
    end)
end

local function scratch(title, lines)
    vim.cmd("botright new")
    local buf = vim.api.nvim_get_current_buf()
    vim.bo[buf].buftype, vim.bo[buf].bufhidden, vim.bo[buf].swapfile = "nofile", "wipe", false
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.list_extend({ title, "" }, lines))
    vim.bo[buf].modifiable = false
    vim.keymap.set("n", "q", "<cmd>close<CR>", { buffer = buf, silent = true })
end

function M.balances()
    local account = M.token_at(vim.fn.getline("."), vim.fn.col("."))
    if account and (account:sub(1, 1) == "#" or account:sub(1, 1) == "^") then account = nil end
    local row = vim.fn.line(".")
    -- Stop at another directive instead of accidentally inspecting an older transaction.
    while row > 0 and not vim.fn.getline(row):match("^%d%d%d%d[%-/]%d%d[%-/]%d%d%s") do row = row - 1 end
    if row == 0 or not syntax.transaction(vim.fn.getline(row)) then
        notify("Place the cursor inside a transaction"); return
    end
    M.request({ action = "balances", file = vim.api.nvim_buf_get_name(0), line = row, account = account },
        function(result)
            local lines = { "Transaction date: " .. result.date, "Inventories in Beancount transaction order.", "" }
            for _, item in ipairs(result.accounts) do
                table.insert(lines, item.account)
                table.insert(lines, "  Before: " .. (#item.before > 0 and table.concat(item.before, "; ") or "0"))
                table.insert(lines, "  After:  " .. (#item.after > 0 and table.concat(item.after, "; ") or "0"))
                table.insert(lines, "")
            end
            scratch("Beancount balances", lines)
        end)
end

function M.query(opts)
    local text, directive = opts.args, false
    if text == "" then
        if opts.range > 0 then
            text = table.concat(vim.api.nvim_buf_get_lines(0, opts.line1 - 1, opts.line2, false), "\n")
        else text, directive = vim.fn.getline("."), true end
    end
    M.request({ action = "query", query = text, directive = directive }, function(result)
        -- Escape embedded newlines so every result row remains one display line.
        local function cell(value) return tostring(value):gsub("\n", "\\n"):gsub("\t", "\\t") end
        local widths, rows = {}, { result.columns }
        vim.list_extend(rows, result.rows)
        for _, row in ipairs(rows) do
            for col, value in ipairs(row) do
                widths[col] = math.max(widths[col] or 0, vim.fn.strdisplaywidth(cell(value)))
            end
        end
        local lines = {}
        for _, row in ipairs(rows) do
            local cells = {}
            for col, value in ipairs(row) do
                value = cell(value)
                cells[col] = value .. string.rep(" ", widths[col] - vim.fn.strdisplaywidth(value))
            end
            table.insert(lines, table.concat(cells, " | "))
        end
        table.insert(lines, "")
        table.insert(lines, tostring(#result.rows) .. " rows")
        scratch("Beancount query", lines)
    end)
end

function M.setup()
    vim.api.nvim_create_user_command("BeancountReferences", function(opts)
        M.references(opts.args ~= "" and opts.args or nil)
    end, { nargs = "?", desc = "Find account, tag, or link references across the ledger" })
    vim.api.nvim_create_user_command("BeancountBalance", M.balances,
        { desc = "Show account inventories before and after this transaction" })
    vim.api.nvim_create_user_command("BeancountQuery", M.query,
        { nargs = "*", range = true, desc = "Run BQL arguments, selected lines, or a query directive" })
end

function M.setup_buffer(buf)
    local key = (config.get("keymaps") or {}).references
    if key and key ~= "" then
        vim.keymap.set("n", key, M.references, { buffer = buf, desc = "Beancount references" })
    end
end

return M
