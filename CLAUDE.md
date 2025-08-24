# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Common Development Commands

### Testing

```bash
make test           # Run all tests using nvim headless mode
```

### Code Quality

```bash
make lint           # Run luacheck on lua/ directory (requires luacheck)
make clean          # Clean up test artifacts
```

### Installation Requirements

- `luacheck` - Lua linter: `luarocks install luacheck`

## Architecture Overview

This is a comprehensive Neovim plugin for Beancount plain text accounting, ported from the VSCode extension. The plugin provides syntax highlighting, diagnostics, auto-completion, formatting, navigation, and snippets.

### Core Module Structure

**Main Entry Point**: `lua/beancount/init.lua`

- Orchestrates plugin initialization and buffer setup
- Sets up autocommands for FileType and BufWritePost events
- Coordinates all feature modules

**Configuration**: `lua/beancount/config.lua`

- Centralized configuration management with validation
- Supports legacy vim global variables for backward compatibility
- Uses dot notation for nested configuration access

### Feature Modules

**Diagnostics**: `lua/beancount/diagnostics.lua`

- Real-time error checking using Python's beancount library via `pythonFiles/beancheck.py`
- Integrates with Neovim's diagnostic system

**Completion**: `lua/beancount/completion.lua`

- Core completion logic for accounts, payees, commodities, tags, links
- `completion/blink.lua` - Integration with blink.cmp completion engine

**Formatting**: `lua/beancount/formatter.lua`

- Instant alignment on decimal point entry
- Auto-indentation and posting alignment

**Navigation**: `lua/beancount/navigation.lua`

- Go-to-definition, account jumping, transaction navigation

**Other Features**:

- `inlay_hints.lua` - Shows inferred amounts as virtual text
- `snippets.lua` - Code snippets for Beancount directives
- `symbols.lua` - Document symbol provider
- `fold.lua` - Code folding support
- `health.lua` - Health check functionality

### Python Integration

**beancheck.py**: Core Python script that interfaces with the beancount library

- Parses beancount files and extracts accounts, commodities, payees, etc.
- Returns structured JSON data for completion and diagnostics
- Handles flag warnings and automatic posting detection

### File Type Integration

**ftdetect/beancount.lua**: Detects `.beancount` and `.bean` files
**ftplugin/beancount.lua**: Sets buffer options, keymaps, and initializes plugin features

### Testing Structure

Tests are located in `tests/` directory and use Neovim's headless mode:

- Each module has corresponding `*_test.lua` files
- Tests run via `nvim --headless --noplugin --clean -c "luafile tests/file.lua"`
- Example beancount files in `tests/example/` for testing

### Configuration System

The plugin uses a sophisticated configuration system:

- Default values in `config.lua` with validation schema
- Deep merging of user options with defaults
- Runtime configuration updates supported
- Legacy vim global variable compatibility

### Key Dependencies

- **Python**: Required for beancount library integration
- **blink.cmp**: Optional but recommended completion engine
- **LuaSnip**: Optional snippet engine support
- **nvim-treesitter**: Optional for enhanced syntax highlighting

## Development Notes

- All Lua code follows 4-space indentation
- Comments use `;;` prefix for beancount files
- The plugin is designed to be lazy-loaded on beancount filetypes
- Buffer setup is idempotent (prevents duplicate initialization)
