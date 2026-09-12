-- Beancount navigation and document link module
-- Provides go-to-definition, file navigation, and document link functionality
local M = {}

-- Namespace for document link highlighting
M.namespace = vim.api.nvim_create_namespace("beancount_document_links")
-- Cache of document links by buffer
M.links = {}

-- Main go-to-definition function
-- Handles accounts (goto open directive) and include statements (goto file)
M.goto_definition = function()
  local line = vim.fn.getline(".")
  if line:match('^%s*include%s+"') then return M.goto_include_file(line) end
  local account = require("beancount.syntax").account_at(line, vim.fn.col("."))
  if account then M.goto_account_definition(account) end
end

M.goto_account_definition = function(account)
  if not account or account == "" then return end
  -- Unsaved local definitions are immediately navigable; compare full tokens.
  for row, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
    local name = line:match("^%d%d%d%d[%-/]%d%d[%-/]%d%d%s+open%s+(%S+)")
    if name == account then vim.api.nvim_win_set_cursor(0, { row, 0 }); return end
  end
  local json = require("beancount.diagnostics").get_completion_data()
  local data = json and vim.json.decode(json)
  local entry = data and data.accounts[account]
  if entry and entry.file and entry.line then
    vim.cmd("edit " .. vim.fn.fnameescape(entry.file))
    vim.api.nvim_win_set_cursor(0, { entry.line, 0 })
    return
  end
  vim.notify("Account definition unavailable; wait for ledger validation: " .. account, vim.log.levels.WARN)
end

-- Extract include filename from line and navigate to it
-- @param line string: Line containing include statement
M.goto_include_file = function(line)
  local filename = line:match('include%s+"([^"]*)"')
  if not filename then
    return
  end

  M.open_include_file(filename)
end

-- Open an included file with smart path resolution
-- @param filename string: Filename to open (may be relative)
M.open_include_file = function(filename)
  if not filename then
    return
  end

  local current_dir = vim.fn.expand("%:p:h")
  local full_path = filename:match("^/") and filename or current_dir .. "/" .. filename
  local matches = vim.fn.glob(full_path, false, true)
  local function open(path)
    if path then vim.cmd("edit " .. vim.fn.fnameescape(path)) end
  end
  if #matches == 1 then open(matches[1])
  elseif #matches > 1 then vim.ui.select(matches, { prompt = "Included file:" }, open)
  else vim.notify("Include file not found: " .. filename, vim.log.levels.WARN) end
end

-- List all known accounts in quickfix window
-- Uses completion data if available for comprehensive account list
M.list_accounts = function()
  local accounts = {}

  -- Try to get accounts from cached completion data
  local diagnostics = require("beancount.diagnostics")
  local completion_data = diagnostics.get_completion_data()

  if completion_data then
    local ok, data = pcall(vim.json.decode, completion_data)
    if ok and data and data.accounts then
      for account, details in pairs(data.accounts) do
        table.insert(accounts, {
          text = account,
          filename = details.file,
          lnum = details.line or 1,
          col = 1,
          type = "account",
          info = details.open and ("Opened: " .. details.open) or "",
        })
      end
    end
  end

  if #accounts > 0 then
    vim.fn.setqflist(accounts, "r")
    pcall(vim.cmd, "copen")
  else
    vim.notify("No accounts found", vim.log.levels.WARN)
  end
end

-- Navigate to the next transaction in the current buffer
local function move_transaction(direction)
  local count, start = vim.fn.line("$"), vim.fn.line(".")
  for offset = 1, count do
    local row = ((start - 1 + direction * offset) % count) + 1
    if require("beancount.syntax").transaction(vim.fn.getline(row)) then
      vim.api.nvim_win_set_cursor(0, { row, 0 })
      return
    end
  end
end
M.next_transaction = function() move_transaction(1) end
M.prev_transaction = function() move_transaction(-1) end

-- Find all document links (include statements) in a buffer
-- @param bufnr number: Buffer to search for links
-- @return table: Array of link objects with ranges and targets
M.find_document_links = function(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local links = {}

  for line_num, line in ipairs(lines) do
    local start, filename = line:match('^%s*include%s+()"([^"]+)"')
    if filename then
      table.insert(links, {
        range = { start = { line = line_num - 1, character = start - 1 },
          ["end"] = { line = line_num - 1, character = start + #filename + 1 } },
        target = filename, tooltip = "Follow link to " .. filename,
      })
    end
  end

  return links
end

-- Update and highlight document links in a buffer
-- @param bufnr number: Buffer to update links for
M.update_document_links = function(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Remove any existing link highlights
  vim.api.nvim_buf_clear_namespace(bufnr, M.namespace, 0, -1)

  -- Find all links and add highlighting
  local links = M.find_document_links(bufnr)
  M.links[bufnr] = links

  for _, link in ipairs(links) do
    vim.api.nvim_buf_add_highlight(
      bufnr,
      M.namespace,
      "Underlined",
      link.range.start.line,
      link.range.start.character,
      link.range["end"].character
    )
  end
end

-- Handle mouse click on a document link
-- @param bufnr number: Buffer number
-- @param line number: Line number (0-based)
-- @param col number: Column number (0-based)
-- @return boolean: True if click was handled
M.handle_document_link = function(bufnr, line, col)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local links = M.links[bufnr] or {}

  for _, link in ipairs(links) do
    if link.range.start.line == line and col >= link.range.start.character and col <= link.range["end"].character then
      M.open_include_file(link.target)
      return true
    end
  end

  return false
end

-- Initialize document link functionality for a buffer
-- @param bufnr number: Buffer to setup (defaults to current)
M.setup_buffer = function(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Initialize links on setup
  M.update_document_links(bufnr)

  -- Create auto-commands to keep links updated
  local augroup = vim.api.nvim_create_augroup("BeancountDocumentLinks_" .. bufnr, { clear = true })

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = augroup,
    buffer = bufnr,
    callback = function()
      vim.defer_fn(function()
        if vim.api.nvim_buf_is_valid(bufnr) then
          M.update_document_links(bufnr)
        end
      end, 100)
    end,
  })

  -- Enable double-click navigation on links
  vim.keymap.set("n", "<2-LeftMouse>", function()
    local pos = vim.fn.getpos(".")
    local line = pos[2] - 1 -- Convert to 0-based
    local col = pos[3] - 1 -- Convert to 0-based

    if not M.handle_document_link(bufnr, line, col) then
      -- Use default double-click behavior if not on a link
      return "<2-LeftMouse>"
    end
  end, { buffer = bufnr, expr = true, desc = "Follow document link" })

  -- Enable 'gf' key for include file navigation
  vim.keymap.set("n", "gf", function()
    local line = vim.fn.getline(".")
    if line:match('include%s+"[^"]*"') then
      M.goto_include_file(line)
    else
      -- Use standard 'gf' behavior for non-include lines
      pcall(vim.cmd, "normal! gf")
    end
  end, { buffer = bufnr, desc = "Go to file or follow include" })
end

-- Initialize the navigation module globally
M.setup = function() end

return M
