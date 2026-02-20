-- Beancount folding module
-- Provides intelligent code folding for beancount files
-- Groups transactions, directives, and other logical blocks
local M = {}

-- Buffer-local cache for marker nesting levels, keyed on (bufnr, changedtick)
local marker_cache = { bufnr = -1, tick = -1, levels = {} }

local function update_marker_cache()
  local bufnr = vim.api.nvim_get_current_buf()
  local tick = vim.api.nvim_buf_get_changedtick(bufnr)
  if marker_cache.bufnr == bufnr and marker_cache.tick == tick then
    return
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local levels = {}
  local current_level = 0

  for i, line in ipairs(lines) do
    local open_num = line:match("{{{(%d*)")
    local close_num = line:match("}}}(%d*)")

    if open_num then
      local n = tonumber(open_num)
      if n then
        current_level = n
      else
        current_level = current_level + 1
      end
      levels[i] = { marker = "open", level = current_level }
    elseif close_num then
      local n = tonumber(close_num)
      levels[i] = { marker = "close", level = current_level }
      if n then
        current_level = n - 1
      else
        current_level = math.max(0, current_level - 1)
      end
    else
      levels[i] = { marker = nil, level = current_level }
    end
  end

  marker_cache = { bufnr = bufnr, tick = tick, levels = levels }
end

-- Main folding expression function for beancount syntax
-- @return string: Fold level indicator for current line
M.foldexpr = function()
  update_marker_cache()

  local lnum = vim.v.lnum
  local info = marker_cache.levels[lnum] or { marker = nil, level = 0 }
  local base = info.level

  -- Handle fold marker open/close lines
  if info.marker == "open" then
    return ">" .. base
  elseif info.marker == "close" then
    return "<" .. base
  end

  local line = vim.fn.getline(lnum)

  -- Start new fold at transaction lines (YYYY-MM-DD * or !)
  if line:match("^%d%d%d%d%-%d%d%-%d%d%s+[*!]") then
    return ">" .. (base + 1)
  end

  -- Major beancount directives each get their own fold
  -- Directives with date prefix: YYYY-MM-DD <directive>
  if
      line:match("^%d%d%d%d%-%d%d%-%d%d%s+open%s")
      or line:match("^%d%d%d%d%-%d%d%-%d%d%s+close%s")
      or line:match("^%d%d%d%d%-%d%d%-%d%d%s+balance%s")
      or line:match("^%d%d%d%d%-%d%d%-%d%d%s+pad%s")
      or line:match("^%d%d%d%d%-%d%d%-%d%d%s+document%s")
      or line:match("^%d%d%d%d%-%d%d%-%d%d%s+note%s")
      or line:match("^%d%d%d%d%-%d%d%-%d%d%s+event%s")
      or line:match("^%d%d%d%d%-%d%d%-%d%d%s+query%s")
      or line:match("^%d%d%d%d%-%d%d%-%d%d%s+custom%s")
      or line:match("^%d%d%d%d%-%d%d%-%d%d%s+price%s")
      or line:match("^%d%d%d%d%-%d%d%-%d%d%s+open$")
      or line:match("^%d%d%d%d%-%d%d%-%d%d%s+close$")
      or line:match("^%d%d%d%d%-%d%d%-%d%d%s+balance$")
      or line:match("^%d%d%d%d%-%d%d%-%d%d%s+pad$")
      or line:match("^%d%d%d%d%-%d%d%-%d%d%s+document$")
      or line:match("^%d%d%d%d%-%d%d%-%d%d%s+note$")
      or line:match("^%d%d%d%d%-%d%d%-%d%d%s+event$")
      or line:match("^%d%d%d%d%-%d%d%-%d%d%s+query$")
      or line:match("^%d%d%d%d%-%d%d%-%d%d%s+custom$")
      or line:match("^%d%d%d%d%-%d%d%-%d%d%s+price$")
  then
    return ">" .. (base + 1)
  end

  -- Configuration directives (plugins, options, includes) start folds
  if line:match("^plugin") or line:match("^option") or line:match("^include") then
    return ">" .. (base + 1)
  end

  -- Empty lines: return marker level (or "0" if outside markers)
  if line:match("^%s*$") then
    return tostring(base)
  end

  -- Posting lines and metadata continue the current fold
  if line:match("^%s+") then
    return "="
  end

  -- All other lines maintain the current fold level
  return "="
end

return M
