return {
  "folke/which-key.nvim",
  event = "VeryLazy",
  opts = {
		preset = "helix",
				defaults = {},
				spec = {
					{
						mode = { "n", "v" },
						{ "<leader>f", group = "file/find" },
						{ "<leader>g", group = "git", icon = { icon = "", color = "orange"} },
						{ "<leader>m", group = "markdown", icon = {icon = "", color = "blue"} },
						{ "<leader>t", group = "ui", icon = { icon = "󰙵 ", color = "cyan" } },
						{
							"<leader>w",
							group = "windows",
							proxy = "<c-w>",
							expand = function()
								return require("which-key.extras").expand.win()
							end,
						},
						{ "<leader>b", group = "buffer", icon = { icon = "", color = "red" } },
						{ "<leader>d", group = "debug", icon = { icon = "", color = "red" } },
						{ "<leader>j", group = "java", icon = { icon = "", color = "orange" } },
						{ "<leader>c", group = "code", icon = { icon = "", color = "yellow" } },
						{ "<leader>r", group = "refactor", icon = { icon = "", color = "purple" } },
						-- better descriptions
						{ "gx", desc = "Open with system app" },
					},
				},
		},

		keys = {
				{
					"<leader>?",
					function()
						require("which-key").show({ global = false })
					end,
					desc = "Buffer Local Keymaps (which-key)",
				},
		},
}
