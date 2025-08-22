-- Beancount document symbols module
-- Provides document outline functionality by parsing beancount syntax
-- Creates a structured view of transactions, accounts, and directives
local M = {}

-- LSP symbol kind constants for categorizing different beancount elements
-- Maps semantic elements to appropriate LSP symbol types
local SymbolKind = {
	File = 1,
	Module = 2,
	Namespace = 3,
	Package = 4,
	Class = 5,
	Method = 6,
	Property = 7,
	Field = 8,
	Constructor = 9,
	Enum = 10,
	Interface = 11,
	Function = 12,
	Variable = 13,
	Constant = 14,
	String = 15,
	Number = 16,
	Boolean = 17,
	Array = 18,
	Object = 19,
	Key = 20,
	Null = 21,
	EnumMember = 22,
	Struct = 23,
	Event = 24,
	Operator = 25,
	TypeParameter = 26,
}

-- Extract all document symbols from a beancount buffer
-- @param bufnr number: Buffer to parse (defaults to current buffer)
-- @return table: Array of symbol objects with LSP-compatible structure
M.get_document_symbols = function(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local symbols = {}

	for line_num, line in ipairs(lines) do
		local symbol = M.parse_line_for_symbol(line, line_num - 1) -- 0-based line numbers
		if symbol then
			table.insert(symbols, symbol)
		end
	end

	return symbols
end

-- Analyze a single line and extract symbol information if present
-- @param line string: Line text to parse
-- @param line_num number: 0-based line number for position info
-- @return table|nil: Symbol object or nil if no symbol found
M.parse_line_for_symbol = function(line, line_num)
	-- Ignore lines that don't contain meaningful symbols
	if line:match("^%s*$") or line:match("^%s*;") then
		return nil
	end

	-- Parse transaction lines (YYYY-MM-DD * "Payee" "Narration")
	local date, flag, payee, narration = line:match('^(%d%d%d%d%-%d%d%-%d%d)%s+([*!])%s*"?([^"]*)"?%s*"?([^"]*)"?')
	if date and flag then
		local name = payee and payee ~= "" and payee or (narration and narration ~= "" and narration or "Transaction")
		local detail = flag == "*" and "Completed" or "Incomplete"
		if payee and payee ~= "" and narration and narration ~= "" then
			detail = detail .. ": " .. payee .. " - " .. narration
		elseif payee and payee ~= "" then
			detail = detail .. ": " .. payee
		elseif narration and narration ~= "" then
			detail = detail .. ": " .. narration
		end

		return {
			name = string.format("[%s] %s", date, name),
			detail = detail,
			kind = SymbolKind.Event,
			range = {
				start = { line = line_num, character = 0 },
				["end"] = { line = line_num, character = #line },
			},
			selectionRange = {
				start = { line = line_num, character = 0 },
				["end"] = { line = line_num, character = #line },
			},
		}
	end

	-- Parse account opening directives
	local open_date, account, currencies = line:match("^(%d%d%d%d%-%d%d%-%d%d)%s+open%s+([A-Za-z0-9:_-]+)%s*(.*)")
	if open_date and account then
		local detail = "Open account"
		if currencies and currencies ~= "" then
			detail = detail .. " (" .. currencies .. ")"
		end

		return {
			name = account,
			detail = detail,
			kind = SymbolKind.Class,
			range = {
				start = { line = line_num, character = 0 },
				["end"] = { line = line_num, character = #line },
			},
			selectionRange = {
				start = { line = line_num, character = line:find(account) - 1 },
				["end"] = { line = line_num, character = line:find(account) + #account - 1 },
			},
		}
	end

	-- Parse account closing directives
	local close_date, close_account = line:match("^(%d%d%d%d%-%d%d%-%d%d)%s+close%s+([A-Za-z0-9:_-]+)")
	if close_date and close_account then
		return {
			name = close_account,
			detail = "Close account",
			kind = SymbolKind.Class,
			range = {
				start = { line = line_num, character = 0 },
				["end"] = { line = line_num, character = #line },
			},
			selectionRange = {
				start = { line = line_num, character = line:find(close_account) - 1 },
				["end"] = { line = line_num, character = line:find(close_account) + #close_account - 1 },
			},
		}
	end

	-- Parse commodity definition directives
	local commodity_date, commodity = line:match("^(%d%d%d%d%-%d%d%-%d%d)%s+commodity%s+([A-Za-z0-9_-]+)")
	if commodity_date and commodity then
		return {
			name = commodity,
			detail = "Commodity definition",
			kind = SymbolKind.Constant,
			range = {
				start = { line = line_num, character = 0 },
				["end"] = { line = line_num, character = #line },
			},
			selectionRange = {
				start = { line = line_num, character = line:find(commodity) - 1 },
				["end"] = { line = line_num, character = line:find(commodity) + #commodity - 1 },
			},
		}
	end

	-- Parse price definition directives
	local price_date, price_commodity, price_amount, price_currency =
		line:match("^(%d%d%d%d%-%d%d%-%d%d)%s+price%s+([A-Za-z0-9_-]+)%s+([0-9.]+)%s+([A-Za-z0-9_-]+)")
	if price_date and price_commodity then
		return {
			name = string.format("%s @ %s %s", price_commodity, price_amount or "", price_currency or ""),
			detail = "Price definition",
			kind = SymbolKind.Number,
			range = {
				start = { line = line_num, character = 0 },
				["end"] = { line = line_num, character = #line },
			},
			selectionRange = {
				start = { line = line_num, character = 0 },
				["end"] = { line = line_num, character = #line },
			},
		}
	end

	-- Parse balance assertion directives
	local balance_date, balance_account, balance_amount =
		line:match("^(%d%d%d%d%-%d%d%-%d%d)%s+balance%s+([A-Za-z0-9:_-]+)%s+([0-9.-]+%s+[A-Za-z0-9_-]+)")
	if balance_date and balance_account then
		return {
			name = string.format("%s: %s", balance_account, balance_amount or ""),
			detail = "Balance assertion",
			kind = SymbolKind.Property,
			range = {
				start = { line = line_num, character = 0 },
				["end"] = { line = line_num, character = #line },
			},
			selectionRange = {
				start = { line = line_num, character = 0 },
				["end"] = { line = line_num, character = #line },
			},
		}
	end

	-- Parse configuration option directives
	local option_name, option_value = line:match('^option%s+"([^"]+)"%s+"?([^"]*)"?')
	if option_name then
		return {
			name = option_name,
			detail = "Option: " .. (option_value or ""),
			kind = SymbolKind.Variable,
			range = {
				start = { line = line_num, character = 0 },
				["end"] = { line = line_num, character = #line },
			},
			selectionRange = {
				start = { line = line_num, character = line:find(option_name) - 1 },
				["end"] = { line = line_num, character = line:find(option_name) + #option_name - 1 },
			},
		}
	end

	-- Parse plugin loading directives
	local plugin_name = line:match('^plugin%s+"([^"]+)"')
	if plugin_name then
		return {
			name = plugin_name,
			detail = "Plugin",
			kind = SymbolKind.Module,
			range = {
				start = { line = line_num, character = 0 },
				["end"] = { line = line_num, character = #line },
			},
			selectionRange = {
				start = { line = line_num, character = line:find(plugin_name) - 1 },
				["end"] = { line = line_num, character = line:find(plugin_name) + #plugin_name - 1 },
			},
		}
	end

	-- Parse file include directives
	local include_file = line:match('^include%s+"([^"]+)"')
	if include_file then
		return {
			name = include_file,
			detail = "Include file",
			kind = SymbolKind.File,
			range = {
				start = { line = line_num, character = 0 },
				["end"] = { line = line_num, character = #line },
			},
			selectionRange = {
				start = { line = line_num, character = line:find(include_file) - 1 },
				["end"] = { line = line_num, character = line:find(include_file) + #include_file - 1 },
			},
		}
	end

	return nil
end

-- Display all document symbols in a quickfix window
-- @param bufnr number: Buffer to extract symbols from
M.show_document_symbols = function(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local symbols = M.get_document_symbols(bufnr)

	if #symbols == 0 then
		return
	end

	local qf_items = {}
	local filename = vim.api.nvim_buf_get_name(bufnr)

	for _, symbol in ipairs(symbols) do
		table.insert(qf_items, {
			bufnr = bufnr,
			filename = filename,
			lnum = symbol.range.start.line + 1, -- Convert to 1-based
			col = symbol.range.start.character + 1, -- Convert to 1-based
			text = symbol.name,
			type = symbol.detail,
		})
	end

	vim.fn.setqflist(qf_items, "r")
	vim.cmd("copen")
end

-- Initialize the symbols module and register commands
M.setup = function()
	-- Create user command for showing symbols
	vim.api.nvim_create_user_command("BeancountSymbols", function()
		M.show_document_symbols()
	end, { desc = "Show document symbols" })
end

-- Setup buffer-specific symbol functionality
-- @param bufnr number: Buffer to setup (defaults to current)
M.setup_buffer = function(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()

	-- Create buffer-local keymap for listing symbols
	vim.keymap.set("n", "<leader>ls", ":BeancountSymbols<CR>", {
		buffer = bufnr,
		desc = "List document symbols",
		silent = true,
	})
end

return M
