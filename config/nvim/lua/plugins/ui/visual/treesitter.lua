local M = require("utils.GlobalFunctions")

return {
  "nvim-treesitter/nvim-treesitter",
  build = ":TSUpdate",
  lazy = vim.fn.argc(-1) == 0,
  dependencies = {
    { "windwp/nvim-ts-autotag" },
  },
  opts = {
    ensure_installed = M.treesitter_languages,
    sync_install = true,
    auto_install = true,
    indent = { enable = true },
    highlight = {
      enable = true,
      additional_vim_regex_highlighting = true,
    },
  },
}
