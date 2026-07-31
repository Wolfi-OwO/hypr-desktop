return {
	"nvim-treesitter/nvim-treesitter",
	build = ":TSUpdate",
	lazy = vim.fn.argc(-1) == 0, -- load treesitter before opening a file
	dependencies = {
		{ "windwp/nvim-ts-autotag" },
	},
	opts = {
		ensure_installed = {
			-- Web
			"javascript",
			"typescript",
			"tsx",
			"angular",
			"html",
			"css",
			"scss",
			-- The three languages this machine actually writes day to day were
			-- missing here, so Python, Java and Go files fell back to regex
			-- highlighting -- which is also what nvim-treesitter-context and
			-- the mini.ai function text objects need in order to work at all.
			"python",
			"java",
			"go",
			"gomod",
			"kotlin",
			"c",
			"cpp",
			"rust",
			-- Config and markup
			"json",
			"jsonc",
			"yaml",
			"toml",
			"bash",
			"dockerfile",
			"markdown",
			"markdown_inline",
			"regex",
			"diff",
			"gitcommit",
			"gitignore",
			-- Editor internals
			"lua",
			"luadoc",
			"vim",
			"vimdoc",
			"query",
			-- The Quickshell configuration in ~/.config/quickshell is QML.
			"qmljs",
		},
		sync_install = true,
		auto_install = true,
		ignore_install = {},
		indent = { enable = true },
		highlight = {
			enable = true,
			additional_vim_regex_highlighting = true,
		},
	},
}
