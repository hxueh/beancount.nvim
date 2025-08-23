# Makefile for beancount.nvim

.PHONY: test clean lint format help

# Default target
help:
	@echo "Available targets:"
	@echo "  test          - Run tests"
	@echo "  lint          - Run luacheck linter"
	@echo "  format        - Format code with stylua"
	@echo "  format-check  - Check code formatting"
	@echo "  clean         - Clean up test artifacts"
	@echo "  help          - Show this help message"

# Run tests
test:
	@echo "Running tests..."
	@nvim --headless -c "luafile tests/config_test.lua"
	@nvim --headless -c "luafile tests/fold_test.lua"
	@nvim --headless -c "luafile tests/inlay_hints_test.lua"
	@nvim --headless -c "luafile tests/navigation_test.lua"
	@nvim --headless -c "luafile tests/symbols_test.lua"
	@nvim --headless -c "luafile tests/utils_test.lua"

# Run linter
lint:
	@echo "Running luacheck..."
	@luacheck lua/ --globals vim --std luajit --codes 2>/dev/null || echo "luacheck not installed. Install with: luarocks install luacheck"

# Format code
format:
	@echo "Formatting code with stylua..."
	@stylua lua/ tests/ 2>/dev/null || echo "stylua not installed. Install from: https://github.com/JohnnyMorganz/StyLua"

# Check formatting
format-check:
	@echo "Checking code formatting..."
	@stylua --check lua/ tests/ 2>/dev/null || echo "stylua not installed or formatting issues found"

# Clean up test artifacts
clean:
	@echo "Cleaning up test artifacts..."
	@find tests/ -name "*.tmp" -delete 2>/dev/null || true
	@find /tmp -name "*beancount*" -type f -delete 2>/dev/null || true
