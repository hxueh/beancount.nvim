-- Beancount completion module
-- Provides intelligent auto-completion for beancount files including accounts,
-- commodities, payees, dates, tags, links, and more
local M = {}

-- Cached completion data loaded from beancount files
-- Updated via external Python scripts that parse beancount data
M.completion_data = {
  accounts = {},    -- Account names with metadata (balances, currencies, etc.)
  commodities = {}, -- Available currencies and commodities
  payees = {},      -- Payee names from transaction history
  narrations = {},  -- Transaction descriptions from history
  tags = {},        -- Available tags (#tag-name)
  links = {},       -- Available links (^link-name)
}

-- Flag to enable/disable hover functionality for accounts
M.hover_enabled = true

-- Initialize the completion system
-- Sets up integration with blink.cmp completion engine
M.setup = function()
  -- blink.cmp integration works automatically when properly configured
  -- No additional setup required here as the blink source handles everything
end

-- Setup buffer-specific completion triggers and auto-commands
-- @param bufnr number: Buffer number to setup completion for
M.setup_buffer = function(bufnr)
  -- blink.cmp integration - add autocmd to trigger after colon, quotes, and spaces (for currency completion)
  vim.api.nvim_create_autocmd("InsertCharPre", {
    buffer = bufnr,
    callback = function()
      local char = vim.v.char
      if char == ":" or char == '"' then
        -- Trigger completion after colon or quote is inserted
        vim.schedule(function()
          local ok_blink, blink = pcall(require, "blink.cmp")
          if ok_blink then
            blink.show()
          end
        end)
      elseif char == " " then
        -- Only trigger after space if we're after an amount in a posting line
        vim.schedule(function()
          local pos = vim.api.nvim_win_get_cursor(0)
          local line = vim.api.nvim_get_current_line()

          -- Check if this space would be after an amount
          local before_space = line:sub(1, pos[2])

          -- Remove trailing whitespace since we're checking the text before typing the space
          local text_before_typing_space = before_space:gsub("%s+$", "")
          -- Pattern: anywhere in line - account + spaces + amount at end
          local is_after_amount = text_before_typing_space:match("[A-Za-z][a-zA-Z0-9:_-]+%s+%-?%d+%.?%d*$")

          if is_after_amount then
            local ok_blink, blink = pcall(require, "blink.cmp")
            if ok_blink then
              blink.show()
            end
          end
        end)
      end
    end,
  })
end

M.update_data = function(json_data)
  if not json_data or json_data == "" then
    return
  end

  local ok, data = pcall(vim.json.decode, json_data)
  if ok and data then
    M.completion_data = data
  else
    vim.notify("Failed to decode completion JSON data", vim.log.levels.ERROR)
  end
end

-- Get completion items based on context
M.get_completion_items = function(line, col)
  local items = {}
  local word_start = M.get_word_bounds(line, col)
  local word = line:sub(word_start, col - 1)

  -- Determine completion type based on context
  if M.is_date_context(line, col) then
    items = M.get_date_completions(word)
  elseif M.is_account_context(line, col) then
    items = M.get_account_completions(word)
  elseif M.is_commodity_context(line, col) then
    items = M.get_commodity_completions(word, line)
  elseif M.is_payee_context(line, col) then
    items = M.get_payee_completions(word)
  elseif M.is_narration_context(line, col) then
    items = M.get_narration_completions(word)
  elseif M.is_tag_context(line, col) then
    items = M.get_tag_completions(word)
  elseif M.is_link_context(line, col) then
    items = M.get_link_completions(word)
  end

  return items
end

-- Context detection functions
M.is_date_context = function(line, col)
  -- Check if we're at the beginning of a line typing a date
  local before_cursor = line:sub(1, col - 1)

  -- Date patterns: beginning of line with partial date (2, 20, 202, 2024, etc.)
  -- Only trigger at start of line (after optional whitespace)
  return before_cursor:match("^%s*2%d?%d?%d?%-?%d?%d?%-?%d?%d?$")
end

M.is_account_context = function(line, col)
  -- Look for account patterns: Assets:, Liabilities:, etc.
  local before_cursor = line:sub(1, col - 1)

  -- Account completion should only trigger:
  -- 1. At start of line (after optional whitespace/tabs) - for posting lines
  -- 2. After specific beancount keywords that require accounts
  -- 3. When continuing an existing account name (contains colon)

  -- Check if we're at start of line with only whitespace/tabs before
  -- Allow partial account names: "A", "As", "Ass", "Asse", "Assets", etc.
  -- Pattern: start of line, optional whitespace/tabs, then letter + optional account chars
  if before_cursor:match("^[ \t]*[A-Za-z][a-zA-Z0-9:_-]*$") then
    return true
  end

  -- Check if we're continuing an account name (already has colon)
  if
      before_cursor:match("[A-Za-z][a-zA-Z0-9_-]*:[a-zA-Z0-9:_-]*$")
      or before_cursor:match("[A-Za-z][a-zA-Z0-9_-]*:$")
  then
    return true
  end

  -- After specific beancount directives that require accounts
  if
      before_cursor:match("open%s+[a-zA-Z0-9:_-]*$")
      or before_cursor:match("close%s+[a-zA-Z0-9:_-]*$")
      or before_cursor:match("balance%s+[a-zA-Z0-9:_-]*$")
  then
    return true
  end

  return false
end

M.is_commodity_context = function(line, col)
  -- After amounts in posting lines, typically for currencies/commodities
  local before_cursor = line:sub(1, col - 1)

  -- Use the same pattern as the space trigger: account + spaces + amount + space
  local has_account_and_amount = before_cursor:match("[A-Za-z][a-zA-Z0-9:_-]+%s+%-?%d+%.?%d*%s+$")

  return has_account_and_amount ~= nil
end

M.is_payee_context = function(line, col)
  -- After transaction date and flag, first quoted string
  local before_cursor = line:sub(1, col - 1)
  local after_cursor = line:sub(col)

  -- Check if we're right after the date/flag pattern and opening quote
  local after_flag = before_cursor:match('%d%d%d%d%-%d%d%-%d%d%s+[%*%!]%s+"')

  -- Also handle case where cursor is between auto-paired quotes
  local between_quotes = before_cursor:match('%d%d%d%d%-%d%d%-%d%d%s+[%*%!]%s+"$') and after_cursor:match('^"')

  -- Make sure we haven't completed the first quoted string yet
  local no_completed_payee = not before_cursor:match('".+"')

  return (after_flag or between_quotes) and no_completed_payee
end

M.is_narration_context = function(line, col)
  -- After payee, second quoted string
  local before_cursor = line:sub(1, col - 1)
  local after_cursor = line:sub(col)

  -- Check if we're after a completed payee and in the narration quote
  local after_payee = before_cursor:match('".+"%s+"')

  -- Also handle case where cursor is between auto-paired quotes for narration
  local between_narration_quotes = before_cursor:match('".+"%s+"$') and after_cursor:match('^"')

  return after_payee or between_narration_quotes
end

M.is_tag_context = function(line, col)
  local before_cursor = line:sub(1, col - 1)
  return before_cursor:match("#[a-zA-Z0-9_-]*$")
end

M.is_link_context = function(line, col)
  local before_cursor = line:sub(1, col - 1)
  return before_cursor:match("%^[a-zA-Z0-9_-]*$")
end

-- Helper function to extract account name from current posting line
M.get_account_on_line = function(line)
  -- Match posting line pattern: whitespace + account + whitespace + amount
  local account = line:match("^%s+([A-Za-z][a-zA-Z0-9:_-]+)%s+%-?%d+")

  return account
end

-- Helper function to get currencies allowed for a specific account
M.get_account_currencies = function(account_name)
  if not account_name or not M.completion_data.accounts then
    return nil
  end

  local account_info = M.completion_data.accounts[account_name]
  if account_info and account_info.currencies and #account_info.currencies > 0 then
    return account_info.currencies
  end

  return nil
end

-- Helper function to extract operating currencies from options
M.get_operating_currencies = function()
  if not M.completion_data.options then
    return nil
  end

  local operating_currencies = {}
  for _, option in ipairs(M.completion_data.options or {}) do
    if option.key == "operating_currency" and option.value then
      table.insert(operating_currencies, option.value)
    end
  end

  if #operating_currencies > 0 then
    return operating_currencies
  else
    return nil
  end
end

-- Get word boundaries
M.get_word_bounds = function(line, col)
  -- Ensure valid inputs
  line = line or ""
  col = col or #line + 1
  col = math.max(1, math.min(col, #line + 1)) -- Clamp col to valid range

  local word_start = col

  -- Find start of word
  while word_start > 1 and line:sub(word_start - 1, word_start - 1):match("[A-Za-z0-9:_-]") do
    word_start = word_start - 1
  end

  return word_start, col
end

-- Completion item generators
M.get_date_completions = function(prefix)
  local items = {}

  -- Get current date components
  local current_date = os.date("*t")
  local current_year = current_date.year
  local current_month = current_date.month
  local current_day = current_date.day

  -- Generate various date completion options
  local date_options = {}

  -- Current date
  table.insert(date_options, {
    date = string.format("%04d-%02d-%02d", current_year, current_month, current_day),
    desc = "Today",
  })

  -- Yesterday
  local yesterday = os.date("*t", os.time() - 24 * 60 * 60)
  table.insert(date_options, {
    date = string.format("%04d-%02d-%02d", yesterday.year, yesterday.month, yesterday.day),
    desc = "Yesterday",
  })

  -- Tomorrow
  local tomorrow = os.date("*t", os.time() + 24 * 60 * 60)
  table.insert(date_options, {
    date = string.format("%04d-%02d-%02d", tomorrow.year, tomorrow.month, tomorrow.day),
    desc = "Tomorrow",
  })

  -- First of this month
  table.insert(date_options, {
    date = string.format("%04d-%02d-01", current_year, current_month),
    desc = "First of this month",
  })

  -- First of next month
  local next_month = current_month + 1
  local next_year = current_year
  if next_month > 12 then
    next_month = 1
    next_year = next_year + 1
  end
  table.insert(date_options, {
    date = string.format("%04d-%02d-01", next_year, next_month),
    desc = "First of next month",
  })

  -- Filter based on prefix and create completion items
  local prefix_lower = prefix:lower()
  for _, option in ipairs(date_options) do
    if option.date:lower():find("^" .. vim.pesc(prefix_lower)) or prefix == "" then
      table.insert(items, {
        label = option.date,
        kind = 12, -- Value
        detail = option.desc,
        insertText = option.date,
        sortText = option.date, -- Sort by date
      })
    end
  end

  return items
end

M.get_account_completions = function(prefix)
  local items = {}

  -- Handle nil prefix
  if not prefix then
    prefix = ""
  end

  -- Handle completion after colon - find accounts that start with the prefix
  local prefix_lower = prefix:lower()

  for account, details in pairs(M.completion_data.accounts or {}) do
    local account_lower = account:lower()
    local should_include = false

    -- Direct match (prefix is beginning of account)
    if account_lower:find("^" .. vim.pesc(prefix_lower)) then
      should_include = true
      -- Contains match (useful for partial matches)
    elseif account_lower:find(vim.pesc(prefix_lower), 1, true) then
      should_include = true
      -- Special handling when prefix ends with colon - show sub-accounts
    elseif prefix:match(":$") then
      local base_prefix = prefix:sub(1, -2) -- Remove trailing colon
      if account_lower:find("^" .. vim.pesc(base_prefix:lower()) .. ":") then
        should_include = true
      end
    end

    -- Skip closed accounts unless they have a balance (might still be relevant)
    if should_include and details.close and details.close ~= "" then
      -- Only include closed accounts if they have a non-zero balance
      if not details.balance or #details.balance == 0 then
        should_include = false
      else
        -- Check if all balances are zero
        local has_non_zero_balance = false
        for _, balance in ipairs(details.balance) do
          -- Simple check for non-zero amounts (matches pattern like "100.00 USD" but not "0.00 USD")
          if not balance:match("^0%.?0*%s") and not balance:match("^%-0%.?0*%s") then
            has_non_zero_balance = true
            break
          end
        end
        if not has_non_zero_balance then
          should_include = false
        end
      end
    end

    if should_include then
      local description = {}
      if details.balance and #details.balance > 0 then
        table.insert(description, "Balance:\n  " .. table.concat(details.balance, "\n  "))
      end
      if details.open then
        table.insert(description, "Opened: " .. details.open)
      end
      if details.close and details.close ~= "" then
        table.insert(description, "Closed: " .. details.close)
      end

      -- For insertText, determine what should replace the current word
      -- The word boundary includes the entire typed prefix, so we insert the full account
      local insertText = account

      table.insert(items, {
        label = account,
        kind = 6, -- Class
        detail = table.concat(description, "\n----\n"),
        insertText = insertText,
      })
    end
  end

  return items
end

M.get_commodity_completions = function(prefix, line)
  local items = {}

  -- Get account from current line
  local account_name = M.get_account_on_line(line or "")

  -- Determine which currencies to offer based on context
  local available_currencies = nil

  -- First priority: account-specific currencies
  if account_name then
    available_currencies = M.get_account_currencies(account_name)
  end

  -- Second priority: operating currencies from options
  if not available_currencies then
    available_currencies = M.get_operating_currencies()
  end

  -- Third priority: all commodities
  if not available_currencies then
    available_currencies = M.completion_data.commodities or {}
  end

  -- Filter and create completion items
  for _, commodity in ipairs(available_currencies) do
    if commodity:lower():find(prefix:lower(), 1, true) then
      table.insert(items, {
        label = commodity,
        kind = 13, -- Constant
        insertText = commodity,
      })
    end
  end

  return items
end

M.get_payee_completions = function(prefix)
  local items = {}

  -- Regular payee matching
  for _, payee in ipairs(M.completion_data.payees or {}) do
    if payee:lower():find(prefix:lower(), 1, true) then
      table.insert(items, {
        label = payee,
        kind = 1, -- Text
        insertText = payee,
      })
    end
  end

  return items
end

M.get_narration_completions = function(prefix)
  local items = {}

  -- Regular narration matching
  for _, narration in ipairs(M.completion_data.narrations or {}) do
    if narration:lower():find(prefix:lower(), 1, true) then
      table.insert(items, {
        label = narration,
        kind = 1, -- Text
        insertText = narration,
      })
    end
  end

  return items
end

M.get_tag_completions = function(prefix)
  local items = {}
  local clean_prefix = prefix:gsub("^#", "")

  for _, tag in ipairs(M.completion_data.tags or {}) do
    if tag:lower():find(clean_prefix:lower(), 1, true) then
      table.insert(items, {
        label = "#" .. tag,
        kind = 14, -- Keyword
        insertText = tag,
      })
    end
  end

  return items
end

M.get_link_completions = function(prefix)
  local items = {}
  local clean_prefix = prefix:gsub("^%^", "")

  for _, link in ipairs(M.completion_data.links or {}) do
    if link:lower():find(clean_prefix:lower(), 1, true) then
      table.insert(items, {
        label = "^" .. link,
        kind = 17, -- Reference
        insertText = link,
      })
    end
  end

  return items
end

-- Hover provider functionality
M.hover = function(bufnr, line, col)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  if not M.hover_enabled then
    return nil
  end

  -- Get the word under cursor
  local lines = vim.api.nvim_buf_get_lines(bufnr, line, line + 1, false)
  if not lines[1] then
    return nil
  end

  local line_text = lines[1]
  local word_start, word_end = M.get_word_bounds_at_pos(line_text, col + 1)
  local word = line_text:sub(word_start, word_end - 1)

  -- Check if it's an account and we have hover info
  if word:match("^[A-Z][a-zA-Z0-9:_-]*$") and M.completion_data.accounts[word] then
    return M.get_account_hover(word)
  end

  return nil
end

-- Get word boundaries at specific position
M.get_word_bounds_at_pos = function(line, pos)
  local word_start = pos
  local word_end = pos

  -- Find start of word
  while word_start > 1 and line:sub(word_start - 1, word_start - 1):match("[A-Za-z0-9:_-]") do
    word_start = word_start - 1
  end

  -- Find end of word
  while word_end <= #line and line:sub(word_end, word_end):match("[A-Za-z0-9:_-]") do
    word_end = word_end + 1
  end

  return word_start, word_end
end

-- Get hover information for an account
M.get_account_hover = function(account)
  local details = M.completion_data.accounts[account]
  if not details then
    return nil
  end

  local lines = { "# Account: " .. account, "" }

  if details.open then
    table.insert(lines, "**Opened:** " .. details.open)
  end

  if details.close and details.close ~= "" then
    table.insert(lines, "**Closed:** " .. details.close)
  end

  if details.currencies and #details.currencies > 0 then
    table.insert(lines, "**Currencies:** " .. table.concat(details.currencies, ", "))
  end

  if details.balance and #details.balance > 0 then
    table.insert(lines, "")
    table.insert(lines, "## Current Balance")
    for _, balance in ipairs(details.balance) do
      table.insert(lines, "- " .. balance)
    end
  end

  return {
    contents = {
      kind = "markdown",
      value = table.concat(lines, "\n"),
    },
  }
end

-- Show hover information
M.show_hover = function()
  local pos = vim.api.nvim_win_get_cursor(0)
  local line = pos[1] - 1 -- Convert to 0-based
  local col = pos[2]      -- Already 0-based

  local hover_info = M.hover(0, line, col)
  if not hover_info then
    return
  end

  -- Create floating window with hover content
  local content = vim.split(hover_info.contents.value, "\n")

  -- Calculate window dimensions
  local width = 0
  for _, line_content in ipairs(content) do
    width = math.max(width, #line_content)
  end
  width = math.min(width, 80)           -- Max width

  local height = math.min(#content, 20) -- Max height

  -- Create buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, content)
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].modifiable = false

  -- Create window
  local opts = {
    relative = "cursor",
    width = width,
    height = height,
    col = 1,
    row = 1,
    anchor = "NW",
    style = "minimal",
    border = "rounded",
    title = " Hover Info ",
    title_pos = "center",
  }

  local win = vim.api.nvim_open_win(buf, false, opts)

  -- Auto-close on cursor move or escape
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    buffer = vim.api.nvim_get_current_buf(),
    once = true,
    callback = function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end,
  })

  vim.keymap.set("n", "<Esc>", function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end, { buffer = buf, nowait = true })
end

-- Setup hover for buffer
M.setup_hover = function(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Set up keymap for hover
  vim.keymap.set("n", "K", M.show_hover, {
    buffer = bufnr,
    desc = "Show hover information",
    silent = true,
  })
end

-- Check blink.cmp integration status for health checks
M.check_blink_integration = function()
  local ok_blink, _ = pcall(require, "blink.cmp")
  if ok_blink then
    return true, "Available and working"
  else
    return false, "Not installed or not available"
  end
end

return M
