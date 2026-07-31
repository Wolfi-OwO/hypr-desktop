return {
		"CRAG666/betterTerm.nvim",
		lazy = false,
		keys = {
				{
					mode = { 'n', 't' },
					'<leader>ta',
					function()
						require('betterTerm').open()
					end,
					desc = 'Open BetterTerm 0',
				},
				{
					mode = { 'n', 't' },
					'<leader>tf',
					function()
						require('betterTerm').open(1)
					end,
					desc = 'Open BetterTerm 1',
				},
				{
					'<leader>tt',
					function()
						require('betterTerm').select()
					end,
					desc = 'Select terminal',
				}
	},
	opts = {
		position = 'bot',
		size = 20,
		jump_tab_mapping = "<A-$tab>"
	},
}
