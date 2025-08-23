-- Luacheck configuration for beancount.nvim

-- Set the standard to luajit (Neovim uses LuaJIT)
std = "luajit"

-- Define global variables that are available in Neovim
globals = {
  "vim",
}

-- Files to ignore
exclude_files = {
  -- Add any files you want to exclude from linting
}

-- Allow unused arguments (common in Neovim callbacks)
unused_args = false

-- Maximum line length
max_line_length = 120

-- Allow unused loop variables (common with ipairs/pairs)
ignore = {
  "212", -- Unused argument
  "213", -- Unused loop variable
  "614", -- Trailing whitespace in comments
}

-- Additional settings for test files
files["tests/"] = {
  -- Allow defining unused functions in tests (test helper functions)
  ignore = { "211", "212", "213", "214", "614" },
  -- Allow globals commonly used in tests
  globals = {
    "describe",
    "it",
    "before_each",
    "after_each",
    "assert",
    "test_assert", -- Our custom test assertion function
    "run_test",    -- Our custom test runner
  }
}
