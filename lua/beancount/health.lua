local M = {}

local utils = require("beancount.utils")
local config = require("beancount.config")

M.check = function()
  vim.health.start("Beancount.nvim Health Check")

  -- Check Neovim version
  local version = vim.version()
  if vim.version.cmp(version, { 0, 8, 0 }) >= 0 then
    vim.health.ok("Neovim version: " .. version.major .. "." .. version.minor .. "." .. version.patch)
  else
    vim.health.error("Neovim 0.8.0+ required, found: " .. version.major .. "." .. version.minor .. "." .. version.patch)
  end

  -- Check Python
  local python_path = config.get("python_path")
  vim.fn.jobstart({ python_path, "--version" }, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      if data and data[1] then
        vim.health.ok("Python found: " .. data[1])
      end
    end,
    on_exit = function(_, exit_code)
      if exit_code ~= 0 then
        vim.health.error("Python not found at: " .. python_path)
      end
    end,
  })

  -- Check beancount
  vim.fn.jobstart({ python_path, "-c", "import beancount; print(beancount.__version__)" }, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      if data and data[1] then
        vim.health.ok("Beancount found: " .. data[1])
      end
    end,
    on_exit = function(_, exit_code)
      if exit_code ~= 0 then
        vim.health.error("Beancount not found. Install with: pip install beancount")
      end
    end,
  })

  -- Check main bean file
  local main_file = utils.get_main_bean_file()
  if main_file ~= "" then
    if utils.file_exists(main_file) then
      vim.health.ok("Main bean file found: " .. main_file)
    else
      vim.health.error("Main bean file not found: " .. main_file)
    end
  else
    vim.health.info("No main bean file configured")
  end

  -- Check optional dependencies
  local completion = require("beancount.completion")
  local is_working, message = completion.check_blink_integration()

  if is_working then
    vim.health.ok("blink.cmp integration: " .. message)
  else
    vim.health.info("blink.cmp integration: " .. message)
  end

  local ok = pcall(require, "luasnip")
  if ok then
    vim.health.ok("LuaSnip found - snippets available")
  else
    vim.health.info("LuaSnip not found - snippets not available")
  end

  -- Check plugin files
  local plugin_dir = utils.get_plugin_dir()
  local check_script = plugin_dir .. "/pythonFiles/beancheck.py"
  if utils.file_exists(check_script) then
    vim.health.ok("Python check script found")
  else
    vim.health.error("Python check script not found: " .. check_script)
  end
end

return M
