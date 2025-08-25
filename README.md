# Beancount.nvim

A comprehensive Neovim plugin for [Beancount](https://beancount.github.io/) plain text accounting, ported from the popular VSCode extension.

## CI Status Badges

[![CI](https://github.com/hxueh/beancount.nvim/workflows/CI/badge.svg)](https://github.com/hxueh/beancount.nvim/actions)

## Features

- 🎯 **Syntax Highlighting** - Full Beancount syntax support with proper highlighting
- 🔍 **Diagnostics** - Real-time error checking using Python's beancount library
- ⚡ **Auto-completion** - Smart completion for accounts, payees, narrations, commodities, tags, and links
- 🔧 **Auto-formatting** - Instant alignment and formatting of postings and amounts
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

**Recommended Setup with blink.cmp:**

```lua
return {
    "hxueh/beancount.nvim",
    ft = { "beancount", "bean" },
    dependencies = {
        {
            "saghen/blink.cmp",
            optional = true,
            opts = function(_, opts)
                table.insert(opts.sources.default, "beancount")
                opts.sources.providers = opts.sources.providers or {}
                opts.sources.providers.beancount = {
                    name = "beancount",
                    module = "beancount.completion.blink",
                    score_offset = 100,
                    opts = {
                        trigger_characters = { ":", "#", "^", '"', " " },
                    },
                }
                return opts
            end,
        },
        {
            "L3MON4D3/LuaSnip",
        },
    },
    config = function()
        require("beancount").setup({})
        -- Treesitter setup
        require("nvim-treesitter.configs").setup {
            ensure_installed = { "beancount" },
            highlight = { enable = true },
            incremental_selection = { enable = true },
            indent = { enable = true },
        }
    end,
}
```

## Configuration

### Full Configuration

```lua
require("beancount").setup({
  -- Alignment & formatting
  separator_column = 70,        -- Column for decimal separator alignment
  instant_alignment = true,     -- Align amounts on decimal point entry
  fixed_cjk_width = false,      -- Treat CJK characters as 2-width
  auto_format_on_save = true,   -- Auto formatting file on saving

  -- Completion & input
  complete_payee_narration = true,  -- Include payees/narrations

  -- Files & paths
  main_bean_file = "",          -- Path to main beancount file
  python_path = "python",       -- Python executable path

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
  auto_save_before_check = true, -- Auto-save before diagnostics

  -- Features
  inlay_hints = true,           -- Show inferred amounts
  snippets = {
    enabled = true,             -- Enable snippet support
    date_format = "%Y-%m-%d",   -- Date format for snippets
  },

  -- Key mappings (customizable)
  keymaps = {
    goto_definition = "gd",     -- Go to definition
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

### Navigation

- `gd` - Go to account definition
- `K` - Show account hover information (on account names)
- `]]` - Next transaction
- `[[` - Previous transaction

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

## Contributing

Contributions are welcome! Please feel free to submit issues and pull requests.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

This plugin is a port of the excellent [vscode-beancount](https://github.com/Lencerf/vscode-beancount) extension by Lencerf.
