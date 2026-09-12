# AGENTS.md

Neovim plugin for Beancount accounting, with Lua editor features and a Python backend.

## Repository map

- `lua/beancount/init.lua`: plugin initialization, autocommands, and buffer setup.
- `lua/beancount/config.lua`: defaults, validation, runtime updates, and legacy `vim.g` compatibility.
- `lua/beancount/`: feature modules for diagnostics, completion, formatting, navigation, autofill, inlay hints, snippets, symbols, syntax, folding, and health checks.
- `lua/beancount/completion/blink.lua`: optional blink.cmp integration; LuaSnip is also optional.
- `pythonFiles/beancheck.py`: Beancount parsing and JSON results for editor features.
- `ftdetect/` and `ftplugin/`: filetype detection, buffer options, and keymaps.
- `tests/`: Lua and Python tests; fixtures live in `tests/example/`.

## Development

Install Neovim, `uv`, and `luacheck` (`luarocks install luacheck`). Run from the repository root:

```sh
make setup   # Create .venv and install requirements-dev.txt
make test    # Run headless Neovim tests and Python unittest discovery
make lint    # Check lua/ with luacheck
```

Tests share the project Python interpreter. Override it with `make test PYTHON=/absolute/path/to/python`.
Run tests for behavior changes and lint for Lua changes; report failures or checks you could not run.

## Code conventions

- Use 4-space indentation for Lua and keep lines within the 120-character lint limit.
- Add comments explaining what the code does and why it is implemented that way.
- Use `;;` for comments in Beancount fixtures.
- Keep buffer setup idempotent and support filetype-based lazy loading.
- Preserve configuration validation, deep merging, runtime updates, and legacy `vim.g` compatibility.
- Keep optional integrations optional.
- Add regression coverage for fixes and update `README.md` when user-facing behavior or configuration changes.
