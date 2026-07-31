local M = require("utils.GlobalFunctions")
return {
		"nvim-lualine/lualine.nvim",
		event = "VeryLazy",
    dependencies = {
				'DaikyXendo/nvim-material-icon',
		},
		opts = {
				options = {
						theme = M.getCurrentTheme(),
						globalstatus = true,
				},
		}
}
