-- Optional integrations belong to the plugin, so user specs only need opts.
-- lazy.nvim merges this package spec with the user's installed plugins.
return {
  {
    "hxueh/beancount.nvim",
    dependencies = {
      { "saghen/blink.cmp", optional = true },
      { "L3MON4D3/LuaSnip", optional = true },
      {
        "nvim-treesitter/nvim-treesitter",
        optional = true,
        -- Extend user parser lists; a scalar "all" still overrides this default.
        opts_extend = { "ensure_installed" },
        opts = { ensure_installed = { "beancount" } },
      },
    },
  },
}
