-- Beancount formatter module
-- Handles automatic text alignment and formatting for beancount files
-- Provides instant alignment of amounts and automatic indentation
local M = {}

local config = require("beancount.config")

-- Initialize the formatter module
-- No global setup required
M.setup = function()
  -- No global initialization needed
end

-- Setup buffer-specific formatting auto-commands
-- @param bufnr number: Buffer number to setup formatting for
M.setup_buffer = function(bufnr)
  -- Create auto-commands for real-time formatting as user types
  local augroup = vim.api.nvim_create_augroup("BeancountFormatter_" .. bufnr, { clear = true })

  vim.api.nvim_create_autocmd("InsertCharPre", {
    group = augroup,
    buffer = bufnr,
    callback = function()
      M.handle_char_insert()
    end,
  })

  vim.api.nvim_create_autocmd("TextChangedI", {
    group = augroup,
    buffer = bufnr,
    callback = function()
      M.handle_text_change()
    end,
  })

  -- Enable automatic formatting when saving files if configured
  if config.get("auto_format_on_save") then
    vim.api.nvim_create_autocmd("BufWritePre", {
      group = augroup,
      buffer = bufnr,
      callback = function()
        -- Format the entire buffer before saving
        M.format_buffer()
      end,
    })
  end
end

-- Handle character insertion for instant alignment
-- Triggers alignment when decimal points are typed
M.handle_char_insert = function()
  local char = vim.v.char

  if char == "." and config.get("instant_alignment") then
    vim.defer_fn(function()
      M.align_current_line()
    end, 10)
  end
end

-- Handle text changes for smart indentation
-- Automatically indents posting lines after transaction headers
M.handle_text_change = function()
  local line_num = vim.fn.line(".")
  local line = vim.fn.getline(line_num)

  -- Detect if user added a new line after a transaction header
  if line_num > 1 then
    local prev_line = vim.fn.getline(line_num - 1)
    local trans_pattern = "^%d%d%d%d%-%d%d%-%d%d%s+[*!]"

    if prev_line:match(trans_pattern) and line == "" then
      M.indent_posting_line(line_num)
    end
  end
end

M.align_current_line = function()
  local line_num = vim.fn.line(".")
  local line = vim.fn.getline(line_num)
  local col = vim.fn.col(".")

  -- Check if we just inserted a decimal point in a posting line
  if M.is_posting_line(line) and line:find("%.", col - 1) then
    M.align_amount(line_num)
  end
end

M.is_posting_line = function(line)
  if not line or type(line) ~= "string" then
    return false
  end
  -- Posting lines start with whitespace and contain an account
  return line:match("^%s+[A-Z][a-zA-Z0-9:_-]+") ~= nil
end

M.align_amount = function(line_num)
  local line = vim.fn.getline(line_num)
  local separator_col = config.get("separator_column")

  -- Parse the posting line to get account and amount
  local indent, account, amount = line:match("^(%s+)([A-Z][a-zA-Z0-9:_-]+)%s+(.*)$")
  if not indent or not account or not amount then
    return
  end

  -- Find decimal point in amount
  local amount_with_decimal = amount:match("([%-+]?%d[%d,]*%.)")
  if not amount_with_decimal then
    -- No decimal point, fall back to old logic
    local account_part = indent .. account .. " "
    local account_len = vim.fn.strdisplaywidth(account_part)
    local target_col = separator_col

    if account_len < target_col then
      local padding = target_col - account_len
      local new_line = account_part .. string.rep(" ", padding) .. amount
      vim.fn.setline(line_num, new_line)
    end
    return
  end

  -- Calculate padding needed to align decimal point
  local content_before = indent .. account
  local content_before_width = M.display_width(content_before)
  local amount_before_decimal_width = M.display_width(amount_with_decimal) - 1 -- -1 for the decimal point

  -- Target position for decimal point (separator_col - 1, like VSCode)
  local target_decimal_pos = separator_col - 1
  local needed_padding = target_decimal_pos - content_before_width - amount_before_decimal_width

  if needed_padding > 0 then
    local new_line = content_before .. string.rep(" ", needed_padding) .. amount

    -- Replace the line
    vim.fn.setline(line_num, new_line)

    -- Restore cursor position, accounting for the padding change
    local old_len = #line
    local new_len = #new_line
    local col = vim.fn.col(".")
    if col > content_before_width then
      vim.fn.cursor(line_num, col + (new_len - old_len))
    end
  end
end

M.indent_posting_line = function(line_num)
  local indent
  if vim.bo.expandtab then
    indent = string.rep(" ", vim.fn.shiftwidth())
  else
    indent = "\t"
  end

  vim.fn.setline(line_num, indent)
  vim.fn.cursor(line_num, #indent + 1)
end

-- Format a complete transaction block
M.format_transaction = function(start_line, end_line)
  if not start_line then
    start_line = vim.fn.line(".")
  end

  if not end_line then
    end_line = start_line
    -- Find the end of the current transaction
    local line_count = vim.fn.line("$")
    while end_line < line_count do
      local line = vim.fn.getline(end_line + 1)
      if line:match("^%s*$") or line:match("^%d%d%d%d%-%d%d%-%d%d") then
        break
      end
      end_line = end_line + 1
    end
  end

  local separator_col = config.get("separator_column")

  for line_num = start_line + 1, end_line do
    local line = vim.fn.getline(line_num)
    if M.is_posting_line(line) then
      M.format_posting_line(line_num, separator_col)
    end
  end
end

M.format_posting_line = function(line_num, separator_col)
  local line = vim.fn.getline(line_num)

  -- Parse the posting line
  local indent, account, amount = line:match("^(%s+)([A-Z][a-zA-Z0-9:_-]+)%s+(.*)$")
  if not indent or not account or not amount then
    return
  end

  -- Find decimal point in amount (like VSCode: /([\-|\+]?)(?:\d|\d[\d,]*\d)(\.)/)
  local amount_with_decimal = amount:match("([%-+]?%d[%d,]*%.)")
  if not amount_with_decimal then
    -- No decimal point found, use old logic
    local account_part = indent .. account
    local account_width = M.display_width(account_part)
    if account_width < separator_col then
      local padding = separator_col - account_width
      local new_line = account_part .. string.rep(" ", padding) .. amount
      vim.fn.setline(line_num, new_line)
    end
    return
  end

  -- Calculate where decimal point should be positioned
  local content_before = indent .. account
  local content_before_width = M.display_width(content_before)
  local amount_before_decimal_width = M.display_width(amount_with_decimal) - 1 -- -1 for the decimal point itself

  -- Target position for decimal point (separator_col - 1, like VSCode)
  local target_decimal_pos = separator_col - 1
  local needed_padding = target_decimal_pos - content_before_width - amount_before_decimal_width

  if needed_padding > 0 then
    local new_line = content_before .. string.rep(" ", needed_padding) .. amount
    vim.fn.setline(line_num, new_line)
  end
end

-- Calculate display width, considering CJK characters if configured
M.display_width = function(text)
  if config.get("fixed_cjk_width") then
    local width = 0
    for _, char in require("utf8").codes(text) do
      if M.is_cjk_char(char) then
        width = width + 2
      else
        width = width + 1
      end
    end
    return width
  else
    return vim.fn.strdisplaywidth(text)
  end
end

-- Check if character is CJK (Chinese, Japanese, Korean)
M.is_cjk_char = function(codepoint)
  return (codepoint >= 0x4E00 and codepoint <= 0x9FFF) -- CJK Unified Ideographs
    or (codepoint >= 0x3400 and codepoint <= 0x4DBF) -- CJK Extension A
    or (codepoint >= 0x20000 and codepoint <= 0x2A6DF) -- CJK Extension B
    or (codepoint >= 0x3040 and codepoint <= 0x309F) -- Hiragana
    or (codepoint >= 0x30A0 and codepoint <= 0x30FF) -- Katakana
    or (codepoint >= 0xAC00 and codepoint <= 0xD7AF) -- Hangul
end

-- Format the entire buffer
M.format_buffer = function()
  local line_count = vim.fn.line("$")
  local separator_col = config.get("separator_column")

  -- Debug: track how many lines we're formatting
  local formatted_lines = 0

  for line_num = 1, line_count do
    local line = vim.fn.getline(line_num)

    -- Format posting lines within transactions
    if M.is_posting_line(line) then
      M.format_posting_line(line_num, separator_col)
      formatted_lines = formatted_lines + 1
    end
  end

  -- Debug: uncomment to see formatting activity
  if formatted_lines == 0 then
    vim.notify("No posting lines found to format", vim.log.levels.WARN)
  end
end

-- Manual format command for testing
M.format_current_buffer = function()
  M.format_buffer()
end

return M
