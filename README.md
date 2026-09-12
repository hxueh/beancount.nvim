# Beancount.nvim

A comprehensive Neovim plugin for [Beancount](https://beancount.github.io/) plain text accounting, ported from the popular VSCode extension.

## CI Status Badges

[![CI](https://github.com/hxueh/beancount.nvim/workflows/CI/badge.svg)](https://github.com/hxueh/beancount.nvim/actions)

## Features

- 🎯 **Syntax Highlighting** - Full Beancount syntax support with proper highlighting
- 🔍 **Diagnostics** - Real-time error checking using Python's beancount library
- ⚡ **Auto-completion** - Smart completion for accounts, payees, narrations, commodities, tags, and links
- 🔧 **Auto-formatting** - Instant alignment and formatting of postings and amounts
- ✨ **Auto-fill Amounts** - Automatically fill missing transaction amounts on save
- 📝 **Snippets** - Comprehensive snippet collection for all Beancount directives
- 🧭 **Navigation** - Go-to-definition, account jumping, and smart folding
- 🎨 **Treesitter** - Modern syntax highlighting and indentation (when available)

## Requirements

- Neovim 0.8.0+
- Python 3.6+
- `beancount` Python package (`pip install beancount`)
- Optional: [blink.cmp](https://github.com/saghen/blink.cmp) for enhanced completion
- Optional: [LuaSnip](https://github.com/L3MON4D3/LuaSnip) for snippets

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
return {
  "hxueh/beancount.nvim",
  ft = "beancount",
  opts = {},
}
```

The plugin finds the nearest `main.bean` or `main.beancount` above the current
file, stopping at a Git repository boundary. If neither exists, it checks the
current file. Python is selected from the ledger's `.venv`, then `VIRTUAL_ENV`,
then `python3` or `python` on PATH. The selected environment must contain Beancount.
Explicit `main_bean_file` and `python_path` options override detection.

If Blink or LuaSnip is installed, the plugin uses it automatically. Its bundled
`lazy.lua` also adds the Beancount parser to the legacy nvim-treesitter `master`
branch's `ensure_installed` list without replacing other languages. On the
current `main` branch, install it with `:TSInstall beancount` instead. With other
plugin managers, install the parser through your Treesitter configuration.

The plugin starts Treesitter highlighting for Beancount buffers automatically
when the parser is available; no extra FileType autocommand is needed. Treesitter
is optional, and a missing parser does not prevent other editor features from
loading. If you install the parser after opening a buffer, run
`:lua vim.treesitter.start()` in that buffer or reopen the file.

To keep automatic amount filling enabled, use `opts = { auto_fill_amounts = true }`.
Alignment already defaults to column 70.

With other plugin managers, `require("beancount").setup({})` accepts the same
options. Opening a Beancount file also initializes the plugin with defaults.

## Configuration

### Full Configuration

```lua
require("beancount").setup({
  -- Alignment & formatting
  separator_column = 70,        -- Column for decimal separator alignment
  instant_alignment = true,     -- Align amounts on decimal point entry
  fixed_cjk_width = false,      -- Treat CJK characters as 2-width
  auto_format_on_save = true,   -- Auto formatting file on saving
  auto_fill_amounts = false,    -- Auto-fill missing amounts on save (opt-in)

  -- Completion & input
  complete_payee_narration = true,  -- Include payees/narrations

  -- Files & paths
  main_bean_file = "",          -- Auto-detect main.bean/main.beancount
  python_path = "",             -- Auto-detect Python; set a path to override

  -- Diagnostics & warnings
  flag_warnings = {             -- Transaction flag warning levels
    ["*"] = nil,                           -- FLAG_OKAY - Transactions that have been checked
    ["!"] = vim.diagnostic.severity.WARN, -- FLAG_WARNING - Mark by user as something to be looked at later
    ["P"] = nil,                           -- FLAG_PADDING - Transactions created from padding directives
    ["S"] = nil,                           -- FLAG_SUMMARIZE - Transactions created due to summarization
    ["T"] = nil,                           -- FLAG_TRANSFER - Transactions created due to balance transfers
    ["C"] = nil,                           -- FLAG_CONVERSIONS - Transactions created to account for price conversions
    ["M"] = nil,                           -- FLAG_MERGING - A flag to mark postings merging together legs for average cost
  },
  validation_debounce_ms = 250, -- Wait after edits before checking
  validation_timeout_ms = 10000, -- Timeout for each check, including autofill

  -- Features
  inlay_hints = true,           -- Show inferred amounts
  snippets = {
    enabled = true,             -- Enable snippet support
    date_format = "%Y-%m-%d",   -- Date format for snippets
  },

  -- Key mappings (customizable)
  keymaps = {
    goto_definition = "gd",     -- Go to definition
    references = "gr",          -- Find account, tag, or link references
    next_transaction = "]]",    -- Next transaction
    prev_transaction = "[[",    -- Previous transaction
  },

  -- UI settings
  ui = {
    virtual_text = true,        -- Show diagnostics as virtual text
    signs = true,               -- Show diagnostic signs
    update_in_insert = false,   -- Don't update while typing
    severity_sort = true,       -- Sort by severity
  },
})
```

## Usage

### Auto-completion

The plugin provides intelligent completion for:

- **Account names** - Complete account hierarchies
- **Payees and narrations** - Based on transaction history
- **Commodities** - Currency and commodity symbols
- **Tags** - Transaction tags with `#`
- **Links** - Transaction links with `^`

**Completion Engine Support**:

- **blink.cmp** - Automatically configured when available (recommended)

The plugin will automatically set up blink.cmp integration including trigger characters for `:`, `#`, `^`, `"`, and space to provide seamless completion experience.

### Formatting

- **Instant alignment**: Amounts align automatically when you type `.`
- **Auto-indent**: New posting lines are automatically indented
- **Manual formatting**: Available via lua functions (no default keymap)

### Auto-fill Missing Amounts

Automatically fill in missing amounts in incomplete transactions when you save a file. This feature is **opt-in** (disabled by default).

**Enable in your config:**
```lua
require("beancount").setup({
    auto_fill_amounts = true,
})
```

**Example:**
```beancount
; Before save
2025-10-10 * "AAPL" "Stock Purchase"
  Assets:Stock                      100.00 AAPL {200.00 USD}
  Expenses:Trading                  2.00 USD
  Assets:Cash

; After save - amount automatically filled
2025-10-10 * "AAPL" "Stock Purchase"
  Assets:Stock                      100.00 AAPL {200.00 USD}
  Expenses:Trading                  2.00 USD
  Assets:Cash                       -20002.00 USD
```

**Requirements:**
- Only works when **exactly one** posting is missing an amount
- Accounts must be properly opened
- Works with multi-currency transactions

**Note:** When `auto_fill_amounts` is enabled, inlay hints are automatically disabled to avoid showing redundant information since amounts are being filled directly.

**Validation performance:** Background checks allow one running process and one
pending request per ledger. `validation_debounce_ms` controls the delay after
editing, and `validation_timeout_ms` limits each process. Outdated results are
discarded. Editor snapshots do not read, overwrite, or delete ledger disk caches.

Autofill skips validation when there are no omitted units. Otherwise it performs
up to two synchronous checks: one to infer amounts and one to
validate the proposed changes. Each has the configured timeout, so a large ledger
can still pause a save. These checks request only errors and inferred amounts;
background checks omit detailed booked postings and unconfigured flags. Process
failures are reported, and failed checks leave inferred amounts unapplied.

### Navigation

- `gd` - Go to account definition
- `K` - Show account hover information (on account names)
- `]]` - Next transaction
- `[[` - Previous transaction

### Ledger exploration

- `gr` or `:BeancountReferences` finds the account, `#tag`, or `^link` under the
  cursor across the loaded ledger, including included files. Results open in
  quickfix with source locations and transaction descriptions. Use `:cnext`,
  `:cprevious`, or Enter to jump. You can also pass a token explicitly:
  `:BeancountReferences Assets:Cash`. Set `keymaps.references = ""` to disable `gr`.
- `:BeancountBalance` shows inventories immediately before and after the current
  transaction. On an account token it shows that account; elsewhere in the
  transaction it shows all posted accounts. Balances follow Beancount's loaded
  transaction order, including same-day entries, and retain currencies and cost
  lots. They are exact-account inventories, without child-account aggregation or
  market-price conversion. The existing `K` hover continues to show the inventory
  over the entire loaded ledger.
- `:BeancountQuery SELECT account, sum(position) GROUP BY account` runs BQL and
  opens a result table. With no argument, it runs the `query` directive on the
  cursor line. A line range, including a visual line selection, supplies raw BQL:
  `:'<,'>BeancountQuery`. Supported statements are `SELECT`, `BALANCES`, and
  `JOURNAL`. Install the optional `beanquery` package in the Python environment
  selected by the plugin (`python -m pip install beanquery`). Other features do
  not require it.

Balance and query results open in read-only scratch windows; press `q` to close.
All three commands load fresh editor snapshots asynchronously and use
`validation_timeout_ms`. A newer exploration request for the same ledger replaces
an earlier one. If a captured buffer changes while a request runs, rerun the
command. These operations do not save or rewrite ledger files. References may
show partial results when the ledger has errors; balances and queries require a
valid ledger. Tags inherited through `pushtag` match their transactions, and
account definitions are included in reference results. Text in comments and
quoted descriptions does not count as a reference.

### Folding

The plugin provides intelligent code folding for Beancount files. All multi-line constructs automatically fold to their first line for better readability:

**Supported directives:**

- **Transactions** (`*`, `!`) - Fold to show only date, flag, payee, and narration
- **Account directives** (`open`, `close`, `balance`, `pad`) - Fold metadata and postings
- **Information directives** (`document`, `note`, `event`, `query`, `custom`, `price`) - Fold multi-line content
- **Configuration** (`plugin`, `option`, `include`) - Fold directive blocks

**Example:**

```beancount
2025-10-10 * "Apple" "iPhone"          ; <- Folded view shows only this line
    Expenses:Phone     1000.00 USD     ; <- Hidden when folded
    Assets:Wallet     -1000.00 USD     ; <- Hidden when folded
```

Use Neovim's standard folding commands: `zo` (open), `zc` (close), `za` (toggle), `zM` (close all), `zR` (open all).

### Snippets

The plugin includes snippets for all Beancount directives:

- `txn*` - Completed transaction
- `txn!` - Incomplete transaction
- `open` - Open account
- `close` - Close account
- `balance` - Balance assertion
- `option` - Plugin option
- And many more...

### Inlay Hints (Automatic Posting Detection)

The plugin shows **inlay hints** for automatically calculated posting amounts. These hints appear when:

- **Incomplete transactions**: When postings don't sum to zero and beancount can infer the missing amount
- **Complex transactions**: Transactions with more than 2 postings OR multiple currencies
- **Configuration enabled**: `inlay_hints = true` in your config
- **Auto-fill disabled**: Inlay hints are automatically disabled when `auto_fill_amounts = true` to avoid redundancy

**Examples:**

Shows hints (complex transaction):

```beancount
2023-01-01 * "Grocery shopping"
  Assets:Checking      -50.00 USD
  Expenses:Food         30.00 USD
  Expenses:Household              ; <- hint shows: 20.00 USD
```

No hints (simple 2-posting transaction):

```beancount
2023-01-01 * "Simple transfer"
  Assets:Checking      -100.00 USD
  Assets:Savings                  ; <- no hint (obvious: +100.00 USD)
```

Hints update automatically when you save the file or when diagnostics run.

## File Structure

The plugin follows standard Neovim conventions:

```
neovim/
├── lua/beancount/          # Main plugin code
│   ├── completion/         # Completion engine integrations
│   │   └── blink.lua      # blink.cmp integration
│   ├── init.lua           # Main module initialization
│   ├── config.lua         # Configuration management
│   ├── completion.lua     # Core completion functionality
│   ├── diagnostics.lua    # Error checking and reporting
│   ├── formatter.lua      # Text formatting and alignment
│   ├── autofill.lua       # Auto-fill missing amounts
│   ├── navigation.lua     # Navigation and jumping features
│   ├── snippets.lua       # Code snippets
│   ├── inlay_hints.lua    # Inferred amount hints
│   ├── symbols.lua        # Symbol provider
│   ├── fold.lua           # Code folding
│   ├── utils.lua          # Utility functions
│   └── health.lua         # Health check
├── ftplugin/beancount.lua  # Filetype settings and keymaps
├── ftdetect/beancount.lua  # File detection (.beancount, .bean)
└── pythonFiles/           # Python integration scripts
    └── beancheck.py       # Beancount file parser and checker
```

## Development

Install `uv`, Neovim, and `luacheck`, then run:

```sh
make setup
make test
make lint
```

`make setup` creates or reuses `.venv` and installs the Beancount version pinned in
`requirements-dev.txt`. Tests use that interpreter for both Python tests and
Neovim integration tests. To use an existing environment, run
`make test PYTHON=/absolute/path/to/python`. Test and lint failures return a
nonzero exit status.

## Contributing

Contributions are welcome! Please feel free to submit issues and pull requests.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

This plugin is a port of the excellent [vscode-beancount](https://github.com/Lencerf/vscode-beancount) extension by Lencerf.
