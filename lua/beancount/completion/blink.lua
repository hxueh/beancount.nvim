-- Blink.cmp source implementation for beancount completion
-- Integrates the beancount completion system with the blink.cmp completion engine
-- Handles context-aware completion for accounts, currencies, payees, and more
-- Main module table for the blink.cmp source
local M = {}

-- Create a new instance of the blink.cmp source
-- @return table: New source instance with metatable setup
M.new = function()
  return setmetatable({}, { __index = M })
end

-- Main completion function called by blink.cmp
-- @param _ table: Source instance (unused)
-- @param context table: Completion context from blink.cmp
-- @param callback function: Callback to return completion results
M.get_completions = function(_, context, callback)
  local completion = require("beancount.completion")

  -- Get actual cursor position directly from Neovim API
  -- blink.cmp's context cursor position can be unreliable in some cases
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line_num = cursor[1] - 1 -- Convert to 0-based
  local col = cursor[2] + 1 -- Convert to 1-based

  -- Fetch the current line content from the buffer
  local lines = vim.api.nvim_buf_get_lines(0, line_num, line_num + 1, false)
  local line = lines[1] or ""

  -- Calculate word boundaries to determine what text should be replaced
  local word_start, _ = completion.get_word_bounds(line, col)

  -- Delegate to our beancount completion system for context-aware items
  local items = completion.get_completion_items(line, col)

  -- Transform our completion items into blink.cmp's expected format
  local blink_items = {}
  for _, item in ipairs(items) do
    table.insert(blink_items, {
      label = item.label,
      kind = item.kind or require("blink.cmp.types").CompletionItemKind.Text,
      detail = item.detail,
      insertText = item.insertText or item.label,
      documentation = item.documentation,
      textEdit = {
        range = {
          start = { line = line_num, character = word_start - 1 }, -- Convert to 0-based
          ["end"] = { line = line_num, character = col - 1 }, -- Convert to 0-based
        },
        newText = item.insertText or item.label,
      },
    })
  end

  callback({
    is_incomplete_forward = false,
    is_incomplete_backward = false,
    items = blink_items,
  })
end

-- Resolve completion item (add additional details if needed)
-- @param _ table: Source instance (unused)
-- @param item table: Completion item to resolve
-- @param callback function: Callback with resolved item
M.resolve = function(_, item, callback)
  callback(item)
end

-- Execute completion item (handle special insertion logic)
-- @param _ table: Source instance (unused)
-- @param item table: Completion item to execute
-- @param callback function: Callback with execution result
M.execute = function(_, item, callback)
  if type(callback) == "table" and callback.textEdit then
    local textEdit = callback.textEdit
    local range = textEdit.range
    local newText = textEdit.newText

    -- Apply the text edit using Neovim's buffer API
    vim.api.nvim_buf_set_text(
      0,
      range.start.line,
      range.start.character,
      range["end"].line,
      range["end"].character,
      vim.split(newText, "\n")
    )

    -- Position cursor at the end of the newly inserted text
    local lines = vim.split(newText, "\n")
    local last_line_idx = range.start.line + #lines - 1
    local last_line_col = #lines > 1 and #lines[#lines] or range.start.character + #newText

    vim.api.nvim_win_set_cursor(0, { last_line_idx + 1, last_line_col })
  end
end

return M
