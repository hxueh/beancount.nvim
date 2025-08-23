# GitHub Actions Workflows

This directory contains the CI/CD workflows for beancount.nvim.

## Workflows

### 🚀 Quick Tests (`test-quick.yml`)

- **Trigger**: Push/PR to `main` branch
- **Purpose**: Fast feedback for essential functionality
- **Runtime**: ~2-3 minutes
- **Matrix**: Neovim stable only

### 🧪 Full CI Pipeline (`ci.yml`)

- **Trigger**: Push/PR to `main` or `develop` branches
- **Purpose**: Comprehensive testing and code quality checks
- **Runtime**: ~5-10 minutes
- **Components**:
  - **Lint Job**: Luacheck static analysis + StyLua formatting checks
  - **Test Job**: Unit tests on Neovim stable + nightly
  - **Test Minimal**: Tests with minimal Neovim configuration

### 📋 Test Suite (`test.yml`)

- **Trigger**: Push/PR to `main` or `develop` branches
- **Purpose**: Focused unit testing across Neovim versions
- **Matrix**: Neovim stable + nightly
- **Features**: Individual test module debugging on failure

## CI Status Badges

Add these to your README.md:

```markdown
[![Tests](https://github.com/hxueh/beancount.nvim/workflows/Tests/badge.svg)](https://github.com/hxueh/beancount.nvim/actions)
[![CI](https://github.com/hxueh/beancount.nvim/workflows/CI/badge.svg)](https://github.com/hxueh/beancount.nvim/actions)
```

## Local Development

Run the same checks locally:

```bash
# Run tests
make test

# Run linter
make lint

# Format code
make format

# Check formatting
make format-check
```

## Test Coverage

Current test modules:

- ✅ **Config Tests** (15 tests) - Configuration management
- ✅ **Fold Tests** (45 tests) - Folding functionality
- ✅ **Inlay Hints Tests** (20 tests) - Inlay hints rendering
- ✅ **Navigation Tests** (28 tests) - Navigation and linking
- ✅ **Symbols Tests** - Symbol parsing and handling
- ✅ **Utils Tests** - Utility functions

**Total**: 108+ comprehensive test cases
