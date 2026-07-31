-- Editing quality-of-life.
--
-- These were configured once in lua/nmask/, a plugin tree that init.lua never
-- imported -- so none of it was actually loaded. The tree is archived at
-- ~/.config/nvim-backup-20260731/nmask; the parts worth keeping live here, in
-- the tree lazy really reads.

return {
	-- ------------------------------------------------------------------
	--  Git in the gutter
	-- ------------------------------------------------------------------
	-- lazygit was already installed, but that is a separate full-screen UI.
	-- gitsigns is the other half: which lines changed, right where you are
	-- editing them, plus staging and blame without leaving the buffer.
	{
		"lewis6991/gitsigns.nvim",
		event = { "BufReadPre", "BufNewFile" },
		opts = {
			signs = {
				add = { text = "▎" },
				change = { text = "▎" },
				delete = { text = "" },
				topdelete = { text = "" },
				changedelete = { text = "▎" },
				untracked = { text = "▎" },
			},
			current_line_blame_opts = { delay = 400, virt_text_pos = "eol" },

			on_attach = function(buffer)
				local gs = package.loaded.gitsigns
				local map = function(mode, l, r, desc)
					vim.keymap.set(mode, l, r, { buffer = buffer, desc = "Git: " .. desc })
				end

				-- ]h / [h mirror ]d / [d for diagnostics, so hunk and
				-- diagnostic navigation feel like the same motion.
				map("n", "]h", function()
					if vim.wo.diff then
						vim.cmd.normal({ "]c", bang = true })
					else
						gs.nav_hunk("next")
					end
				end, "next hunk")
				map("n", "[h", function()
					if vim.wo.diff then
						vim.cmd.normal({ "[c", bang = true })
					else
						gs.nav_hunk("prev")
					end
				end, "previous hunk")

				map({ "n", "v" }, "<leader>gs", gs.stage_hunk, "stage hunk")
				map({ "n", "v" }, "<leader>gr", gs.reset_hunk, "reset hunk")
				map("n", "<leader>gS", gs.stage_buffer, "stage buffer")
				map("n", "<leader>gR", gs.reset_buffer, "reset buffer")
				map("n", "<leader>gp", gs.preview_hunk_inline, "preview hunk")
				map("n", "<leader>gb", function()
					gs.blame_line({ full = true })
				end, "blame line")
				map("n", "<leader>gB", gs.toggle_current_line_blame, "toggle inline blame")
				map("n", "<leader>gd", gs.diffthis, "diff against index")
				map({ "o", "x" }, "ih", gs.select_hunk, "select hunk")
			end,
		},
	},

	-- ------------------------------------------------------------------
	--  TODO / FIXME / HACK highlighting
	-- ------------------------------------------------------------------
	{
		"folke/todo-comments.nvim",
		event = { "BufReadPost", "BufNewFile" },
		dependencies = { "nvim-lua/plenary.nvim" },
		opts = { signs = true },
		keys = {
			{ "<leader>ft", "<cmd>TodoTelescope<cr>", desc = "Find TODOs" },
			{ "<leader>ct", "<cmd>TodoTrouble<cr>", desc = "TODOs in Trouble" },
			{
				"]t",
				function()
					require("todo-comments").jump_next()
				end,
				desc = "Next TODO comment",
			},
			{
				"[t",
				function()
					require("todo-comments").jump_prev()
				end,
				desc = "Previous TODO comment",
			},
		},
	},

	-- ------------------------------------------------------------------
	--  Sticky scope header
	-- ------------------------------------------------------------------
	-- Pins the enclosing function or class to the top of the window while
	-- scrolling through a long body -- the single most useful thing when
	-- reading unfamiliar code, and the thing IDEs have that Neovim does not
	-- out of the box.
	{
		"nvim-treesitter/nvim-treesitter-context",
		event = { "BufReadPost", "BufNewFile" },
		dependencies = { "nvim-treesitter/nvim-treesitter" },
		opts = {
			max_lines = 3, -- deeper than this eats the window
			multiline_threshold = 1,
			separator = "─",
		},
		keys = {
			{
				"<leader>tc",
				function()
					require("treesitter-context").toggle()
				end,
				desc = "Toggle sticky context header",
			},
		},
	},

	-- ------------------------------------------------------------------
	--  mini.nvim modules
	-- ------------------------------------------------------------------
	-- mini.nvim is already installed as a render-markdown dependency but no
	-- module was ever enabled. These three are the ones that were configured
	-- in the dead tree, as separate plugins each; taking them from mini costs
	-- nothing extra since the plugin is on disk either way.
	{
		"echasnovski/mini.nvim",
		event = "VeryLazy",
		config = function()
			-- ai: treat functions, classes and arguments as text objects, so
			-- vaf selects a whole function and cia changes an argument.
			require("mini.ai").setup({ n_lines = 500 })

			-- surround: sa/sd/sr add, delete and replace brackets and quotes.
			require("mini.surround").setup()

			-- pairs: auto-close brackets and quotes.
			require("mini.pairs").setup()

			-- comment: gcc for a line, gc for a motion. Uses treesitter to pick
			-- the right comment syntax, which matters in mixed files like
			-- .vue or .astro where // and <!-- --> both appear.
			require("mini.comment").setup()
		end,
	},
}
