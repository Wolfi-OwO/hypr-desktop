-- Formatting through conform.nvim.
--
-- This replaces the none-ls setup that was here before. none-ls works by
-- pretending to be a language server so that vim.lsp.buf.format() reaches the
-- formatters, which means every format request competes with the real servers
-- -- the old config had to filter ESLint out by hand for exactly that reason.
-- conform calls the formatter binaries directly, so there is nothing to
-- arbitrate, it can chain several formatters over one buffer, and it falls back
-- to the LSP only where no formatter is configured.
--
-- The behaviour of the old setup is kept: <C-f>i formats, and web files format
-- on save.

return {
	{
		"stevearc/conform.nvim",
		event = { "BufWritePre" },
		cmd = { "ConformInfo" },
		keys = {
			{
				"<C-f>i",
				function()
					require("conform").format({ async = true, lsp_format = "fallback" })
				end,
				mode = { "n", "v" },
				desc = "Format buffer or selection",
			},
			{
				"<leader>tf",
				function()
					vim.g.disable_autoformat = not vim.g.disable_autoformat
					vim.notify(
						"Format on save " .. (vim.g.disable_autoformat and "disabled" or "enabled"),
						vim.log.levels.INFO
					)
				end,
				desc = "Toggle format on save",
			},
		},

		opts = {
			formatters_by_ft = {
				lua = { "stylua" },

				-- Sub-lists run in sequence: isort orders the imports, black
				-- then reformats everything including them. The reverse order
				-- would let black reflow imports that isort is about to move.
				python = { "isort", "black" },

				javascript = { "prettierd", "prettier", stop_after_first = true },
				javascriptreact = { "prettierd", "prettier", stop_after_first = true },
				typescript = { "prettierd", "prettier", stop_after_first = true },
				typescriptreact = { "prettierd", "prettier", stop_after_first = true },
				vue = { "prettierd", "prettier", stop_after_first = true },
				svelte = { "prettierd", "prettier", stop_after_first = true },
				css = { "prettierd", "prettier", stop_after_first = true },
				scss = { "prettierd", "prettier", stop_after_first = true },
				less = { "prettierd", "prettier", stop_after_first = true },
				html = { "prettierd", "prettier", stop_after_first = true },
				json = { "prettierd", "prettier", stop_after_first = true },
				jsonc = { "prettierd", "prettier", stop_after_first = true },
				yaml = { "prettierd", "prettier", stop_after_first = true },
				markdown = { "prettierd", "prettier", stop_after_first = true },

				java = { "google-java-format" },
				go = { "gofmt" },
				sh = { "shfmt" },
				bash = { "shfmt" },

				-- Trim trailing whitespace in anything not listed above.
				["_"] = { "trim_whitespace" },
			},

			format_on_save = function(bufnr)
				-- Escape hatch for the times a file has to be saved exactly as
				-- it is: <leader>tf, or :lua vim.g.disable_autoformat = true
				if vim.g.disable_autoformat or vim.b[bufnr].disable_autoformat then
					return
				end

				-- Only the filetypes the previous config formatted on save.
				-- Reformatting an entire unfamiliar Python or Java file on the
				-- first save produces a diff nobody asked for, so those stay
				-- explicit through <C-f>i.
				local on_save = {
					javascript = true,
					javascriptreact = true,
					typescript = true,
					typescriptreact = true,
					json = true,
					jsonc = true,
					css = true,
					scss = true,
					less = true,
					html = true,
					vue = true,
					svelte = true,
					markdown = true,
					yaml = true,
					lua = true,
				}
				if not on_save[vim.bo[bufnr].filetype] then
					return
				end

				return { timeout_ms = 1000, lsp_format = "fallback" }
			end,

			formatters = {
				shfmt = { prepend_args = { "-i", "2", "-ci" } },
				-- Match the .stylua.toml in this config directory when
				-- formatting files that live outside a project of their own.
				stylua = {
					prepend_args = { "--config-path", vim.fn.stdpath("config") .. "/.stylua.toml" },
				},
			},
		},

		init = function()
			-- Make gq use conform, so the built-in format operator lines up
			-- with what saving does.
			vim.o.formatexpr = "v:lua.require'conform'.formatexpr()"
			vim.g.disable_autoformat = false
		end,
	},
}
