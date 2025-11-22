-- Beancount folding module
-- Provides intelligent code folding for beancount files
-- Groups transactions, directives, and other logical blocks
local M = {}

-- Main folding expression function for beancount syntax
-- @return string: Fold level indicator for current line
M.foldexpr = function()
  local line = vim.fn.getline(vim.v.lnum)

  -- Start new fold at transaction lines (YYYY-MM-DD * or !)
  if line:match("^%d%d%d%d%-%d%d%-%d%d%s+[*!]") then
    return ">1"
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
    return ">1"
  end

  -- Configuration directives (plugins, options, includes) start folds
  if line:match("^plugin") or line:match("^option") or line:match("^include") then
    return ">1"
  end

  -- Empty lines close the current fold level
  if line:match("^%s*$") then
    return "0"
  end

  -- Posting lines and metadata continue the current fold
  if line:match("^%s+") then
    return "="
  end

  -- All other lines maintain the current fold level
  return "="
end

return M
