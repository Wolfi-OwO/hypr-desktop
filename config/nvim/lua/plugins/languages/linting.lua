-- Linters that are not language servers.
--
-- Most diagnostics here come from an LSP already (eslint for TS/JS, pyright for
-- Python types, jdtls for Java). What is missing is the class of checks no
-- language server does: shell scripts have no LSP-provided linter at all, and
-- ruff catches the style and correctness issues pyright ignores because they
-- are not type errors.
--
-- nvim-lint runs the binaries and pushes the results into the same
-- vim.diagnostic namespace the language servers use, so Trouble and the
-- diagnostic keymaps see them without any extra wiring.

return {
	{
		"mfussenegger/nvim-lint",
		event = { "BufReadPost", "BufNewFile", "BufWritePost" },
		config = function()
			local lint = require("lint")

			lint.linters_by_ft = {
				sh = { "shellcheck" },
				bash = { "shellcheck" },
				python = { "ruff" },
			}

			-- Linting on every keystroke is distracting and, for shellcheck,
			-- wasteful. These three events cover "I stopped typing", "I saved"
			-- and "I opened the file".
			local group = vim.api.nvim_create_augroup("nvim_lint", { clear = true })
			vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "InsertLeave" }, {
				group = group,
				callback = function()
					-- try_lint errors when the linter binary is missing; that is
					-- a normal state before mason-tool-installer has run, and
					-- an error message on every buffer switch would be worse
					-- than silently having no shell diagnostics.
					pcall(lint.try_lint)
				end,
			})

			vim.keymap.set("n", "<leader>l", function()
				lint.try_lint()
			end, { desc = "Lint current buffer" })
		end,
	},
}
