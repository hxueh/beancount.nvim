# Makefile for beancount.nvim

.DEFAULT_GOAL := help

.PHONY: test clean lint help setup

# Keep Python tests and Neovim subprocesses on the same project interpreter.
PYTHON ?= $(CURDIR)/.venv/bin/python
export BEANCOUNT_TEST_PYTHON := $(PYTHON)
export PATH := $(dir $(PYTHON)):$(PATH)

setup:
	@test -x .venv/bin/python || uv venv .venv
	@uv pip install --python .venv/bin/python -r requirements-dev.txt

# Default target
help:
	@echo "Available targets:"
	@echo "  setup         - Install the Python test environment with uv"
	@echo "  test          - Run tests"
	@echo "  lint          - Run luacheck linter"
	@echo "  clean         - Clean up test artifacts"
	@echo "  help          - Show this help message"

# Run tests
test:
	@"$(PYTHON)" -c "import beancount"
	@echo "Running Lua tests..."
	@nvim --headless --noplugin --clean -n -i NONE -c "luafile tests/setup_test.lua"
	@nvim --headless --noplugin --clean -n -i NONE -c "luafile tests/config_test.lua"
	@nvim --headless --noplugin --clean -n -i NONE -c "luafile tests/fold_test.lua"
	@nvim --headless --noplugin --clean -n -i NONE -c "luafile tests/inlay_hints_test.lua"
	@nvim --headless --noplugin --clean -n -i NONE -c "luafile tests/navigation_test.lua"
	@nvim --headless --noplugin --clean -n -i NONE -c "luafile tests/symbols_test.lua"
	@nvim --headless --noplugin --clean -n -i NONE -c "luafile tests/utils_test.lua"
	@nvim --headless --noplugin --clean -n -i NONE -c "luafile tests/completion_blink_test.lua"
	@nvim --headless --noplugin --clean -n -i NONE -c "luafile tests/completion_test.lua"
	@nvim --headless --noplugin --clean -n -i NONE -c "luafile tests/autofill_test.lua"
	@nvim --headless --noplugin --clean -n -i NONE -c "luafile tests/indentation_test.lua"
	@nvim --headless --noplugin --clean -n -i NONE -c "luafile tests/formatter_test.lua"
	@nvim --headless --noplugin --clean -n -i NONE -c "luafile tests/regression_test.lua"
	@nvim --headless --noplugin --clean -n -i NONE -c "luafile tests/validation_test.lua"
	@nvim --headless --noplugin --clean -n -i NONE -c "luafile tests/syntax_test.lua"
	@nvim --headless --noplugin --clean -n -i NONE -c "luafile tests/explorer_test.lua"
	@echo "Running Python tests..."
	@"$(PYTHON)" -m unittest discover -s tests -p '*_test.py'

# Run linter
lint:
	@echo "Running luacheck..."
	@luacheck lua/ --globals vim --std luajit --codes

# Clean up test artifacts
clean:
	@echo "Cleaning up test artifacts..."
	@find tests/ -name "*.tmp" -delete 2>/dev/null || true
	@find /tmp -name "*beancount*" -type f -delete 2>/dev/null || true
