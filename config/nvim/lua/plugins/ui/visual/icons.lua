return {
  {
    "kyazdani42/nvim-web-devicons",
    lazy = false,
    priority = 1001,
    dependencies = {
      "DaikyXendo/nvim-material-icon",
    },
    config = function()
      local ok, material_icons = pcall(require, "nvim-material-icon")
      require("nvim-web-devicons").setup({
        override = ok and material_icons.get_icons() or {},
        default = true,
      })
    end,
  },

  {
    "DaikyXendo/nvim-material-icon",
    lazy = false,
    priority = 1000,
  },
}
