# Makefile for beancount.nvim

.PHONY: test clean help

# Default target
help:
	@echo "Available targets:"
	@echo "  test          - Run tests"
	@echo "  clean         - Clean up test artifacts"
	@echo "  help          - Show this help message"

# Run tests
test:
	@echo "Running tests..."
	@nvim --headless -c "luafile tests/config_test.lua"
	@nvim --headless -c "luafile tests/fold_test.lua"
	@nvim --headless -c "luafile tests/inlay_hints_test.lua"
	@nvim --headless -c "luafile tests/symbols_test.lua"
	@nvim --headless -c "luafile tests/utils_test.lua"

# Clean up test artifacts
clean:
	@echo "Cleaning up test artifacts..."
	@find tests/ -name "*.tmp" -delete 2>/dev/null || true
	@find /tmp -name "*beancount*" -type f -delete 2>/dev/null || true
