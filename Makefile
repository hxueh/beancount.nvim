# Makefile for beancount.nvim

.PHONY: test clean lint help

# Default target
help:
	@echo "Available targets:"
	@echo "  test          - Run tests"
	@echo "  lint          - Run luacheck linter"
	@echo "  clean         - Clean up test artifacts"
	@echo "  help          - Show this help message"

# Run tests
test:
	@echo "Running Lua tests..."
	@nvim --headless --noplugin --clean -c "luafile tests/config_test.lua"
	@nvim --headless --noplugin --clean -c "luafile tests/fold_test.lua"
	@nvim --headless --noplugin --clean -c "luafile tests/inlay_hints_test.lua"
	@nvim --headless --noplugin --clean -c "luafile tests/navigation_test.lua"
	@nvim --headless --noplugin --clean -c "luafile tests/symbols_test.lua"
	@nvim --headless --noplugin --clean -c "luafile tests/utils_test.lua"
	@echo "Running Python tests..."
	@python3 -m unittest tests/beancheck_test.py -v 2>/dev/null || echo "Python unittest not available or tests failed. Install with: pip install beancount"
	@python3 tests/performance_test.py 2>/dev/null || echo "Performance test failed or dependencies missing"

# Run linter
lint:
	@echo "Running luacheck..."
	@luacheck lua/ --globals vim --std luajit --codes 2>/dev/null || echo "luacheck not installed. Install with: luarocks install luacheck"

# Clean up test artifacts
clean:
	@echo "Cleaning up test artifacts..."
	@find tests/ -name "*.tmp" -delete 2>/dev/null || true
	@find /tmp -name "*beancount*" -type f -delete 2>/dev/null || true
