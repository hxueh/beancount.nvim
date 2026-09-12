-- Fill only omitted units. Lot selectors, costs, prices and metadata belong to
-- the author and must not be inferred back from booked postings into source.
local M = { automatics = {}, cost_basis_data = {} }
local config = require("beancount.config")
local syntax = require("beancount.syntax")

function M.update_data(json)
  local ok, data = pcall(vim.json.decode, json or "")
  data = ok and type(data) == "table" and data or {}
  M.automatics = data.automatics or (data.cost_basis and {}) or data
  M.cost_basis_data = data.cost_basis or {}
end

local function canonical(path)
  return vim.loop.fs_realpath(path) or path
end

local function planned_lines(buf)
  local filename = canonical(vim.api.nvim_buf_get_name(buf))
  local entries = {}
  for file, value in pairs(M.automatics) do
    if canonical(file) == filename then entries = value; break end
  end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for row = #lines, 1, -1 do
    local amounts = entries[tostring(row)]
    if type(amounts) == "string" then amounts = { amounts } end
    local indent, account, suffix = syntax.posting(lines[row])
    if amounts and #amounts > 0 and account and (suffix:match("^%s*$") or suffix:match("^%s*;")) then
      -- Expanding a posting with metadata would move that metadata to only the
      -- last generated posting. Leave this ambiguous case to the author.
      local next_line = lines[row + 1] or ""
      local metadata = next_line:match("^%s+[a-z][%w_-]*:%s")
      if #amounts == 1 or not metadata then
        table.remove(lines, row)
        for i = #amounts, 1, -1 do
          local comment = i == 1 and suffix:match("(;.*)$") or nil
          table.insert(lines, row, indent .. account .. "  " .. amounts[i] .. (comment and " " .. comment or ""))
        end
      end
    end
  end
  return lines
end

function M.fill_incomplete_amounts(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local lines = planned_lines(buf)
  if vim.deep_equal(lines, vim.api.nvim_buf_get_lines(buf, 0, -1, false)) then return false end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return true
end

-- Compatibility shim: older callers may still invoke this public function.
-- Returning false preserves their ledger instead of synthesizing cost prices.
function M.enhance_cost_basis() return false end

function M.fill_buffer(buf)
  if not config.get("auto_fill_amounts") then return false end
  buf = buf or vim.api.nvim_get_current_buf()
  -- Most saves contain no omitted units. Skip inference entirely in that case
  -- instead of loading a large ledger only to discover there is nothing to fill.
  local missing = false
  for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    local _, account, suffix = syntax.posting(line)
    if account and (suffix:match("^%s*$") or suffix:match("^%s*;")) then missing = true; break end
  end
  if not missing then M.update_data(nil); return false end
  local diagnostics = require("beancount.diagnostics")
  local fresh = vim.api.nvim_buf_call(buf, diagnostics.check_file_sync)
  if not fresh then M.update_data(nil); return false end
  M.update_data(vim.json.encode(fresh))
  local lines = planned_lines(buf)
  if vim.deep_equal(lines, vim.api.nvim_buf_get_lines(buf, 0, -1, false)) then return false end
  local filename = vim.api.nvim_buf_get_name(buf)
  local valid = vim.api.nvim_buf_call(buf, function()
    return diagnostics.check_file_sync({ [filename] = table.concat(lines, "\n") .. "\n" })
  end)
  if not valid then return false end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  if config.get("auto_format_on_save") then
    vim.api.nvim_buf_call(buf, require("beancount.formatter").format_buffer)
  end
  return true
end

function M.setup_buffer(buf)
  if not config.get("auto_fill_amounts") then return end
  buf = buf or vim.api.nvim_get_current_buf()
  local group = vim.api.nvim_create_augroup("BeancountAutofill_" .. buf, { clear = true })
  -- Validate snapshots before the original write: one save, no recursive writes
  -- and no intermediate file containing unvalidated generated amounts.
  vim.api.nvim_create_autocmd("BufWritePre", {
    group = group, buffer = buf,
    callback = function()
      local ok, err = pcall(M.fill_buffer, buf)
      if not ok then vim.notify("Beancount autofill failed: " .. tostring(err), vim.log.levels.ERROR) end
    end,
  })
end
function M.setup() end
return M
