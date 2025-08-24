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
  local word = vim.fn.expand("<cword>")
  local line = vim.fn.getline(".")

  -- Handle account name navigation to open directive
  if word:match("^[A-Z][a-zA-Z0-9:_-]*$") then
    M.goto_account_definition(word)
    -- Handle include statement navigation to file
  elseif line:match('include%s+"[^"]*"') then
    M.goto_include_file(line)
  end
end

-- Navigate to the open directive for an account
-- @param account string: Account name to find
M.goto_account_definition = function(account)
  if not account or account == "" then
    vim.notify("No account specified", vim.log.levels.WARN)
    return
  end
  -- Create search pattern for account's open directive
  local search_pattern = "\\v^\\d{4}-\\d{2}-\\d{2}\\s+open\\s+" .. vim.fn.escape(account, "\\.*[]^$(){}+?|")

  -- Search in current buffer first for performance
  local pos = vim.fn.search(search_pattern, "nw")
  if pos > 0 then
    vim.fn.cursor(pos, 1)
    pcall(vim.cmd, "normal! zz")
    return
  end

  -- If not found locally, search all beancount files in project
  local files = vim.fn.glob("**/*.beancount", false, true)
  vim.list_extend(files, vim.fn.glob("**/*.bean", false, true))

  for _, file in ipairs(files) do
    local lines = vim.fn.readfile(file)
    for i, line in ipairs(lines) do
      if line:match("^%d%d%d%d%-%d%d%-%d%d%s+open%s+" .. vim.fn.escape(account, "\\.*[]^$(){}+?|")) then
        pcall(vim.cmd, "edit " .. file)
        vim.fn.cursor(i, 1)
        pcall(vim.cmd, "normal! zz")
        return
      end
    end
  end

  vim.notify("Account definition not found: " .. account, vim.log.levels.WARN)
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

  -- Try relative to current file's directory first
  local current_dir = vim.fn.expand("%:h")
  local full_path = current_dir .. "/" .. filename

  if vim.fn.filereadable(full_path) == 1 then
    pcall(vim.cmd, "edit " .. full_path)
  elseif vim.fn.filereadable(filename) == 1 then
    pcall(vim.cmd, "edit " .. filename)
  else
    vim.notify("Include file not found: " .. filename, vim.log.levels.WARN)
  end
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
          filename = vim.fn.expand("%"),
          lnum = 1,
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
M.next_transaction = function()
  local pattern = "^\\d\\{4\\}-\\d\\{2\\}-\\d\\{2\\}\\s\\+[*!]"
  vim.fn.search(pattern)
end

-- Navigate to the previous transaction in the current buffer
M.prev_transaction = function()
  local pattern = "^\\d\\{4\\}-\\d\\{2\\}-\\d\\{2\\}\\s\\+[*!]"
  vim.fn.search(pattern, "b")
end

-- Find all document links (include statements) in a buffer
-- @param bufnr number: Buffer to search for links
-- @return table: Array of link objects with ranges and targets
M.find_document_links = function(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local links = {}

  for line_num, line in ipairs(lines) do
    -- Look for include statements with .beancount extension
    for filename in line:gmatch('include%s+"([^"]+%.beancount)"') do
      local start_pos = line:find('"' .. vim.fn.escape(filename, "\\.*[]^$(){}+?|") .. '"')
      if start_pos then
        table.insert(links, {
          range = {
            start = { line = line_num - 1, character = start_pos - 1 },
            ["end"] = { line = line_num - 1, character = start_pos + #filename + 1 },
          },
          target = filename,
          tooltip = "Follow link to " .. filename,
        })
      end
    end
    -- Also look for include statements with .bean extension
    for filename in line:gmatch('include%s+"([^"]+%.bean)"') do
      local start_pos = line:find('"' .. vim.fn.escape(filename, "\\.*[]^$(){}+?|") .. '"')
      if start_pos then
        table.insert(links, {
          range = {
            start = { line = line_num - 1, character = start_pos - 1 },
            ["end"] = { line = line_num - 1, character = start_pos + #filename + 1 },
          },
          target = filename,
          tooltip = "Follow link to " .. filename,
        })
      end
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
M.setup = function()
  -- Auto-setup navigation for all beancount files
  vim.api.nvim_create_autocmd("FileType", {
    pattern = "beancount",
    callback = function()
      M.setup_buffer()
    end,
  })
end

return M
