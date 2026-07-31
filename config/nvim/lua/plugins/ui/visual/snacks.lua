local dashboard = require("plugins.ui.visual.snacks-components.dashboard")
return {
		"folke/snacks.nvim",
		dependencies = {
				"DaikyXendo/nvim-material-icon",
		},
		enabled = function()
			local arg = vim.fn.argv(0)
			-- Don't load the dashboard if opening a directory
			return arg == "" or vim.fn.isdirectory(arg) == 0
		end,
		priority = 1000,
		lazy = false,
		opts = {
				bigfile = { enabled = true },
				dashboard = dashboard,
				indent = { enabled = true },
				input = { enabled = true },
				picker = { enabled = true },
				notifier = { enabled = true },
				quickfile = { enabled = true },
				scope = { enabled = true },
				scroll = { enabled = true },
				statuscolumn = { enabled = true },
				words = { enabled = true },
		},
}
