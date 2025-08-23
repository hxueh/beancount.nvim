-- Beancount inlay hints module
-- Displays automatic posting amounts as virtual text hints
-- Shows what amounts will be automatically calculated by beancount
local M = {}

local config = require("beancount.config")
local utils = require("beancount.utils")

-- Namespace for virtual text hints
M.namespace = vim.api.nvim_create_namespace("beancount_inlay_hints")
-- Cache of automatic posting data from beancount validation
M.automatics = {}

-- Calculate the position of decimal point in a posting line
-- Used for aligning virtual text hints with existing amounts
-- @param line_text string: Text of the posting line
-- @return number|nil: Position of decimal point or nil if not found
local function get_dot_pos(line_text)
	-- Pattern match: whitespace + account + amount + currency
	local res = line_text:match("%s*(%S+)%s+(%-?[0-9%.]+)(%s*)([a-zA-Z]+)")
	if not res then
		return nil
	end

	local amount_start = line_text:find("%-?[0-9%.]+")
	if not amount_start then
		return nil
	end

	local amount = line_text:match("%-?([0-9%.]+)", amount_start)
	if not amount then
		return nil
	end

	local dot_pos = amount:find("%.")
	if not dot_pos then
		return nil
	end

	return amount_start + dot_pos - 2 -- -1 for 0-based, -1 for dot position
end

-- Calculate padding to align virtual text with decimal points
-- @param dot_pos number: Position where decimal should align
-- @param cur_line string: Current line text
-- @param units string: Units text to display
-- @return string: Padded units string for proper alignment
local function pad_units(dot_pos, cur_line, units)
	local units_dot_pos = units:find("%.")
	if not units_dot_pos then
		units_dot_pos = #units + 1
	end

	local num_spaces = dot_pos - #cur_line - units_dot_pos + 1
	local final_pad = math.max(num_spaces, 1)

	-- Use non-breaking spaces to ensure proper alignment in virtual text
	local space = "\u{00a0}"
	return space:rep(final_pad) .. units
end

-- Update automatic posting data from beancount validation
-- @param data_json string: JSON string containing automatic postings by file and line
M.update_data = function(data_json)
	if not data_json or data_json == "" then
		M.automatics = {}
		return
	end

	local ok, data = pcall(vim.json.decode, data_json)
	if ok and data then
		M.automatics = data
	else
		M.automatics = {}
	end

	-- Refresh hints in all currently visible beancount buffers
	M.update_visible_buffers()
end

-- Check if a buffer has automatic posting data
-- @param bufnr number: Buffer number to check
-- @return boolean: True if buffer has automatic postings
local function is_tracked_buffer(bufnr)
	local filename = vim.api.nvim_buf_get_name(bufnr)
	return M.automatics[filename] ~= nil
end

-- Render virtual text hints for automatic postings in a buffer
-- @param bufnr number: Buffer number to render hints for
M.render_hints = function(bufnr)
	if not config.get("inlay_hints") then
		return
	end

	local filename = vim.api.nvim_buf_get_name(bufnr)
	local file_automatics = M.automatics[filename]

	if not file_automatics then
		return
	end

	-- Remove any existing virtual text before adding new hints
	vim.api.nvim_buf_clear_namespace(bufnr, M.namespace, 0, -1)

	for line_str, units in pairs(file_automatics) do
		local line_num = tonumber(line_str) - 1 -- Convert to 0-based

		if line_num >= 0 and line_num < vim.api.nvim_buf_line_count(bufnr) then
			local line_text = vim.api.nvim_buf_get_lines(bufnr, line_num, line_num + 1, false)[1] or ""

			-- Scan previous posting lines to determine alignment position
			local dot_pos = nil
			for prev_line = line_num - 1, math.max(0, line_num - 10), -1 do
				local prev_text = vim.api.nvim_buf_get_lines(bufnr, prev_line, prev_line + 1, false)[1] or ""

				if prev_text:match("^%s*$") then
					-- Continue searching past empty lines
					goto continue
				end

				if prev_text:match("^%S") then
					-- Stop when we reach transaction header line
					break
				end

				dot_pos = get_dot_pos(prev_text)
				if dot_pos then
					break
				end

				::continue::
			end

			-- Use default separator column if no decimal point found
			if not dot_pos then
				local separator_column = config.get("separator_column")
				dot_pos = (separator_column or 70) - 1
			end

			local hint_text = pad_units(dot_pos, line_text, units)

			-- Display the hint as virtual text at end of line
			vim.api.nvim_buf_set_extmark(bufnr, M.namespace, line_num, -1, {
				virt_text = { { hint_text, "Comment" } },
				virt_text_pos = "eol",
			})
		end
	end
end

-- Refresh inlay hints in all visible beancount buffers
-- Called when automatic posting data is updated
M.update_visible_buffers = function()
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local bufnr = vim.api.nvim_win_get_buf(win)
		if vim.bo[bufnr].filetype == "beancount" and is_tracked_buffer(bufnr) then
			M.render_hints(bufnr)
		end
	end
end

-- Initialize inlay hints for a specific buffer
-- @param bufnr number: Buffer number to setup (defaults to current buffer)
M.setup_buffer = function(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()

	-- Setup auto-commands to refresh hints when buffer changes
	local augroup = vim.api.nvim_create_augroup("BeancountInlayHints_" .. bufnr, { clear = true })

	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "BufWritePost" }, {
		group = augroup,
		buffer = bufnr,
		callback = function()
			vim.defer_fn(function()
				if vim.api.nvim_buf_is_valid(bufnr) then
					M.render_hints(bufnr)
				end
			end, 100)
		end,
	})

	vim.api.nvim_create_autocmd("BufDelete", {
		group = augroup,
		buffer = bufnr,
		callback = function()
			vim.api.nvim_buf_clear_namespace(bufnr, M.namespace, 0, -1)
		end,
	})

	-- Show hints immediately after setup
	M.render_hints(bufnr)
end

-- Initialize the inlay hints module globally
-- Sets up window-level auto-commands for hint management
M.setup = function()
	-- Refresh hints when switching between windows
	vim.api.nvim_create_autocmd("WinEnter", {
		group = vim.api.nvim_create_augroup("BeancountInlayHintsGlobal", { clear = true }),
		callback = function()
			local bufnr = vim.api.nvim_get_current_buf()
			if vim.bo[bufnr].filetype == "beancount" and is_tracked_buffer(bufnr) then
				M.render_hints(bufnr)
			end
		end,
	})
end

return M
