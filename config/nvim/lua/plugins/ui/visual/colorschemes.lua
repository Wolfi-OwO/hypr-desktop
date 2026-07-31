return {
		-- Theme Switcher
		{
				"zaldih/themery.nvim",
				lazy = false,
				keys = {
						{
								"<leader>te",
								function()
										vim.cmd(":Themery")
								end,
								desc = "Thermery (Theme Switcher)",
						},
				},
				opts = {
						themes = {
								{
									name = "VS-Code",
									colorscheme = "vscode",
								},
								{
									name = "catppuccin",
									colorscheme = "catppuccin",
								},
								{
									name = "everforest",
									colorscheme = "everforest",
								},
								{
										name = "xcode",
										colorscheme = "xcode",
								},
								{
										name = "neodark",
										colorscheme = "neodark",
								},
								{
										name = "vim",
										colorscheme = "vim",
								},
								{
										name = "nightfly",
										colorscheme = "nightfly",
								},
								{
										name = "nightfox",
										colorscheme = "nightfox",
								},
						},
				},
		},

		-- Themes
		{
				"catppuccin/nvim",
				name = "catppuccin",
		},
		{
				"Mofiqul/vscode.nvim",
				name = "vscode",
				opts = {
						-- Enable transparent background
						transparent = true,
						-- Enable italic comment
						italic_comments = true,
						-- Underline @markup.link.* variants
						underline_links = true,
						-- Disable nvim-tree background color
						disable_nvimtree_bg = false,
				}
		},
		{
				"sainnhe/everforest",
				name = "everforest"
		},
		{
				"lunacookies/vim-colors-xcode",
				name = "xcode"
		},
		{
				"KeitaNakamura/neodark.vim",
				name = "neodark"
		},
		{
				"bluz71/vim-nightfly-colors",
				name = "nightfly"
		},
		{
				"challenger-deep-theme/vim",
				name = "vim"
		},
		{
				"EdenEast/nightfox.nvim",
				name = "nightfox",
				opts = {
						options = {
								transparent = true
						}
				}
		},
}
