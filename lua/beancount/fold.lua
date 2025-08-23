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
	if
		line:match("^%d%d%d%d%-%d%d%-%d%d%s+open%s")
		or line:match("^%d%d%d%d%-%d%d%-%d%d%s+close%s")
		or line:match("^%d%d%d%d%-%d%d%-%d%d%s+balance%s")
		or line:match("^%d%d%d%d%-%d%d%-%d%d%s+pad%s")
		or line:match("^%d%d%d%d%-%d%d%-%d%d%s+open$")
		or line:match("^%d%d%d%d%-%d%d%-%d%d%s+close$")
		or line:match("^%d%d%d%d%-%d%d%-%d%d%s+balance$")
		or line:match("^%d%d%d%d%-%d%d%-%d%d%s+pad$")
	then
		return ">1"
	end

	-- Configuration directives (plugins and options) start folds
	if line:match("^plugin") or line:match("^option") then
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
