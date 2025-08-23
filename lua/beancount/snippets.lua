-- Beancount snippets module
-- Provides code snippets for common beancount directives and patterns
-- Supports both LuaSnip and UltiSnips snippet engines
local M = {}

-- Get current date formatted according to user configuration
-- @return string: Formatted date string (default ISO format YYYY-MM-DD)
local function current_date()
	local config = require("beancount.config")
	local format = config.get("snippets.date_format") or "%Y-%m-%d"
	return os.date(format)
end

-- Generate LuaSnip snippet definitions for beancount
-- @return table: Array of LuaSnip snippet objects
M.luasnip_snippets = function()
	local ls = require("luasnip")
	local s = ls.snippet
	local t = ls.text_node
	local i = ls.insert_node
	local c = ls.choice_node
	local f = ls.function_node

	return {
		s("option", {
			t('option "'),
			i(1, "name"),
			t('" "'),
			i(2, "value"),
			t('"'),
			t({ "", "" }),
			i(0),
		}),

		s("open", {
			f(current_date),
			t(" open "),
			c(1, {
				t("Assets:"),
				t("Liabilities:"),
				t("Equity:"),
				t("Income:"),
				t("Expenses:"),
			}),
			i(2, "Account"),
			t(" "),
			i(3, "[Currency]"),
			t({ "", "" }),
			i(0),
		}),

		s("close", {
			f(current_date),
			t(" close "),
			c(1, {
				t("Assets:"),
				t("Liabilities:"),
				t("Equity:"),
				t("Income:"),
				t("Expenses:"),
			}),
			i(2, "Account"),
			t({ "", "" }),
			i(0),
		}),

		s("commodity", {
			f(current_date),
			t(" commodity "),
			i(1, "ISO/Ticker"),
			t({ "", '  name: "' }),
			i(2, "FullName"),
			t('"'),
			t({ "", '  asset-class: "' }),
			c(3, { t("cash"), t("stock") }),
			t('"'),
			t({ "", "" }),
			i(0),
		}),

		s("txn*", {
			f(current_date),
			t(' * "'),
			i(1, "Payee"),
			t('" "'),
			i(2, "Narration"),
			t('"'),
			t({ "", "  " }),
			i(0),
		}),

		s("txn!", {
			f(current_date),
			t(' ! "'),
			i(1, "Payee"),
			t('" "'),
			i(2, "Narration"),
			t('"'),
			t({ "", "  " }),
			i(0),
		}),

		s("balance", {
			f(current_date),
			t(" balance "),
			c(1, {
				t("Assets:"),
				t("Liabilities:"),
				t("Equity:"),
				t("Income:"),
				t("Expenses:"),
			}),
			i(2, "Account"),
			t(" "),
			i(3, "Amount"),
			t({ "", "" }),
			i(0),
		}),

		s("pad", {
			f(current_date),
			t(" pad "),
			i(1, "AccountTo"),
			t(" "),
			i(2, "AccountFrom"),
			t({ "", "" }),
			i(0),
		}),

		s("note", {
			f(current_date),
			t(" note "),
			c(1, {
				t("Assets:"),
				t("Liabilities:"),
				t("Equity:"),
				t("Income:"),
				t("Expenses:"),
			}),
			i(2, "Account"),
			t(' "'),
			i(3, "Description"),
			t('"'),
			t({ "", "" }),
			i(0),
		}),

		s("document", {
			f(current_date),
			t(" document "),
			c(1, {
				t("Assets:"),
				t("Liabilities:"),
				t("Equity:"),
				t("Income:"),
				t("Expenses:"),
			}),
			i(2, "Account"),
			t(' "'),
			i(3, "PathToDocument"),
			t('"'),
			t({ "", "" }),
			i(0),
		}),

		s("price", {
			f(current_date),
			t(" price "),
			i(1, "Commodity"),
			t(" "),
			i(2, "Price"),
			t({ "", "" }),
			i(0),
		}),

		s("event", {
			f(current_date),
			t(' event "'),
			i(1, "Key"),
			t('" "'),
			i(2, "Value"),
			t('"'),
			t({ "", "" }),
			i(0),
		}),

		s("plugin", {
			t('plugin "'),
			i(1, "PluginName"),
			t('" "'),
			i(2, "ConfigString"),
			t('"'),
			t({ "", "" }),
			i(0),
		}),

		s("include", {
			t('include "'),
			i(1, "Filename"),
			t('"'),
			t({ "", "" }),
			i(0),
		}),

		s("query", {
			f(current_date),
			t(' query "'),
			i(1, "Name"),
			t('" "'),
			i(2, "SQLContents"),
			t('"'),
			t({ "", "" }),
			i(0),
		}),

		s("custom", {
			f(current_date),
			t(' custom "'),
			i(1, "TypeName"),
			t('" '),
			i(2, "Value..."),
			t({ "", "" }),
			i(0),
		}),

		s("pushtag", {
			t("pushtag #"),
			i(1, "TagName"),
			t({ "", "" }),
			i(0),
		}),

		s("poptag", {
			t("poptag #"),
			i(1, "TagName"),
			t({ "", "" }),
			i(0),
		}),

		s("budget", {
			f(current_date),
			t(' custom "budget" '),
			i(1, "Expenses:Account"),
			t(' "'),
			c(2, {
				t("daily"),
				t("weekly"),
				t("monthly"),
				t("quarterly"),
				t("yearly"),
			}),
			t('" '),
			i(3, "Amount"),
			t({ "", "" }),
			i(0),
		}),
	}
end

-- UltiSnips snippet definitions in text format
-- Users can copy this to their UltiSnips snippet directory
M.ultisnips_snippets = [[
snippet option "Add option" b
option "${1:name}" "${2:value}"
$0
endsnippet

snippet open "Open an account" b
`date +%Y-%m-%d` open ${1:Assets:}${2:Account} ${3:[Currency]}
$0
endsnippet

snippet close "Close an account" b
`date +%Y-%m-%d` close ${1:Assets:}${2:Account}
$0
endsnippet

snippet commodity "Add commodity metadata" b
`date +%Y-%m-%d` commodity ${1:ISO/Ticker}
  name: "${2:FullName}"
  asset-class: "${3:cash}"
$0
endsnippet

snippet txn* "Add completed transaction" b
`date +%Y-%m-%d` * "${1:Payee}" "${2:Narration}"
  $0
endsnippet

snippet txn! "Add incomplete transaction" b
`date +%Y-%m-%d` ! "${1:Payee}" "${2:Narration}"
  $0
endsnippet

snippet balance "Assert balance" b
`date +%Y-%m-%d` balance ${1:Assets:}${2:Account} ${3:Amount}
$0
endsnippet

snippet pad "Pad balance" b
`date +%Y-%m-%d` pad ${1:AccountTo} ${2:AccountFrom}
$0
endsnippet

snippet note "Insert a dated comment" b
`date +%Y-%m-%d` note ${1:Assets:}${2:Account} "${3:Description}"
$0
endsnippet

snippet document "Insert a dated document" b
`date +%Y-%m-%d` document ${1:Assets:}${2:Account} "${3:PathToDocument}"
$0
endsnippet

snippet price "Add a dated price" b
`date +%Y-%m-%d` price ${1:Commodity} ${2:Price}
$0
endsnippet

snippet event "Add a dated event" b
`date +%Y-%m-%d` event "${1:Key}" "${2:Value}"
$0
endsnippet

snippet plugin "Load a plugin" b
plugin "${1:PluginName}" "${2:ConfigString}"
$0
endsnippet

snippet include "Include a beancount file" b
include "${1:Filename}"
$0
endsnippet

snippet query "Insert query" b
`date +%Y-%m-%d` query "${1:Name}" "${2:SQLContents}"
$0
endsnippet

snippet custom "Add custom directive" b
`date +%Y-%m-%d` custom "${1:TypeName}" ${2:Value...}
$0
endsnippet

snippet pushtag "Push a tag onto the stack" b
pushtag #${1:TagName}
$0
endsnippet

snippet poptag "Pop a tag from the stack" b
poptag #${1:TagName}
$0
endsnippet

snippet budget "Add a Fava compatible budget directive" b
`date +%Y-%m-%d` custom "budget" ${1:Expenses:Account} "${2:monthly}" ${3:Amount}
$0
endsnippet
]]

-- Initialize the snippets module
-- Automatically registers snippets with available snippet engines
M.setup = function()
	local config = require("beancount.config")

	-- Respect user's snippet configuration setting
	local snippets_config = config.get("snippets")
	if not snippets_config or not snippets_config.enabled then
		return
	end

	-- Register snippets with LuaSnip if it's installed
	local ok, ls = pcall(require, "luasnip")
	if ok then
		ls.add_snippets("beancount", M.luasnip_snippets())
	end

	-- UltiSnips users need to manually copy snippets to their directory
	-- Access UltiSnips format via M.ultisnips_snippets property
end

return M
