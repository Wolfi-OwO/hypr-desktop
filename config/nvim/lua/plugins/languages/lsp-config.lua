return {
	-- Mason (LSP/DAP/Linter/Formatter installer)
	{
		"williamboman/mason.nvim",
		config = function()
			require("mason").setup({
				ui = {
					border = "rounded",
					icons = { package_installed = "", package_pending = "", package_uninstalled = "" },
				},
			})
		end,
	},

	-- Mason installs LSP servers on demand, but jdtls, the debug adapters and
	-- the formatters are not LSP servers, so mason-lspconfig never sees them.
	-- mason-tool-installer covers everything Mason can install, whatever its
	-- category, so a fresh machine ends up with the full toolchain after one
	-- :Lazy sync instead of a list of "command not found" errors.
	{
		"WhoIsSethDaniel/mason-tool-installer.nvim",
		dependencies = { "williamboman/mason.nvim" },
		config = function()
			require("mason-tool-installer").setup({
				ensure_installed = {
					-- Java: the server plus the two OSGi bundles nvim-jdtls
					-- loads for debugging and test running.
					"jdtls",
					"java-debug-adapter",
					"java-test",
					-- Formatters (driven by conform.nvim)
					"stylua",
					"prettierd",
					"black",
					"isort",
					"google-java-format",
					"shfmt",
					-- Linters (driven by nvim-lint)
					"shellcheck",
					"ruff",
				},
				-- Installing on startup blocks the UI on a fresh clone. Running
				-- it on demand keeps the first launch responsive.
				run_on_start = false,
			})
		end,
	},

	-- Mason + LSP config bridge
	{
		"williamboman/mason-lspconfig.nvim",
		config = function()
			require("mason-lspconfig").setup({
				ensure_installed = {
					"lua_ls",
					"pyright",
					"vtsls", -- better alternative to tsserver
					"eslint", -- linting for TS/JS
					"html",
					"cssls",
					"tailwindcss",
					"angularls",
					"jsonls",
					"yamlls",
					"bashls",
					"dockerls",
					"marksman", -- Markdown
					"gopls",
					-- jdtls is intentionally NOT listed: nvim-jdtls starts it
					-- itself with a per-project workspace and the debug
					-- bundles. Starting it here as well corrupts that
					-- workspace. See plugins/languages/java.lua.
				},

				-- Leaving it out of ensure_installed is not enough. Since v2,
				-- mason-lspconfig enables every server Mason has on disk, and
				-- Mason installs the jdtls package for nvim-jdtls -- so
				-- lspconfig started a second jdtls with the bare `java` from
				-- PATH (17 on this machine), which dies during OSGi startup
				-- and takes the working nvim-jdtls client down with it. The
				-- symptom was a Java buffer with no language server at all and
				-- nothing in :messages.
				automatic_enable = {
					exclude = {
						"jdtls",
						-- vtsls and ts_ls are two front ends for the same
						-- TypeScript service. Mason has both on disk, so both
						-- were being enabled and a .ts buffer ended up with
						-- three servers attached (angularls, ts_ls, vtsls) --
						-- every diagnostic and every completion twice over.
						-- vtsls is the one configured below, so ts_ls goes.
						"ts_ls",
					},
				},
			})
		end,
	},

	-- Core LSP configuration
	{
		"neovim/nvim-lspconfig",
		config = function()
			-- Define configs
			vim.lsp.config.lua_ls = {
				settings = {
		Lua = {
						diagnostics = { globals = { "vim" } },
						workspace = {
							checkThirdParty = false,
							library = vim.api.nvim_get_runtime_file("", true),
						},
						telemetry = { enable = false },
					},
				},
			}

			vim.lsp.config.pyright = {
				before_init = function(_, config)
					local venv = os.getenv("CONDA_PREFIX")
					if venv then
						config.settings = { python = { pythonPath = venv .. "/bin/python" } }
					end
				end,
			}

			vim.lsp.config.vtsls = {}
			vim.lsp.config.eslint = {
				on_attach = function(client)
					client.server_capabilities.documentFormattingProvider = false
					client.server_capabilities.documentRangeFormattingProvider = false
				end,
			}
			vim.lsp.config.html = {}
			vim.lsp.config.cssls = {
				settings = {
					css = { validate = true },
					scss = { validate = true },
					less = { validate = true },
				},
			}
			vim.lsp.config.tailwindcss = {}
			vim.lsp.config.angularls = {
				-- The previous `root_dir = vim.fs.root(0, {...})` was evaluated
				-- once while this file was sourced, against whatever buffer
				-- happened to be current at startup, so the answer was pinned
				-- for the entire session.
				--
				-- Replacing it with root_markers is not enough either: when no
				-- marker matches, Neovim still starts the server in single-file
				-- mode, so angularls attached to every plain TypeScript project
				-- and sat there resolving nothing. A root_dir function that
				-- simply does not call on_dir cancels the start instead.
				root_dir = function(bufnr, on_dir)
					local root = vim.fs.root(bufnr, { "angular.json", "nx.json" })
					if root then
						on_dir(root)
					end
				end,
			}
			vim.lsp.config.jsonls = {
				settings = {
					json = { validate = { enable = true } },
				},
			}
			vim.lsp.config.yamlls = {
				settings = {
					-- yamlls otherwise refuses to format, deferring to a
					-- formatter that is not configured for YAML here.
					yaml = { keyOrdering = false },
				},
			}
			vim.lsp.config.bashls = {}
			vim.lsp.config.dockerls = {}
			vim.lsp.config.marksman = {}
			vim.lsp.config.gopls = {
				settings = {
					gopls = {
						analyses = { unusedparams = true },
						staticcheck = true,
					},
				},
			}

			-- ---------------------------------------------------------------
			--  Buffer-local keymaps
			-- ---------------------------------------------------------------
			-- Set on LspAttach rather than globally, so gd in a buffer with no
			-- language server still does its built-in "go to local definition"
			-- instead of silently doing nothing.
			vim.api.nvim_create_autocmd("LspAttach", {
				group = vim.api.nvim_create_augroup("lsp_keymaps", { clear = true }),
				callback = function(event)
					local map = function(keys, fn, desc, mode)
						vim.keymap.set(mode or "n", keys, fn, { buffer = event.buf, desc = "LSP: " .. desc })
					end

					-- fzf-lua is the picker in this config; its LSP views show
					-- a preview, which the built-in quickfix list does not.
					local ok, fzf = pcall(require, "fzf-lua")

					map("gd", ok and fzf.lsp_definitions or vim.lsp.buf.definition, "go to definition")
					map("gr", ok and fzf.lsp_references or vim.lsp.buf.references, "list references")
					map("gI", ok and fzf.lsp_implementations or vim.lsp.buf.implementation, "go to implementation")
					map("gy", ok and fzf.lsp_typedefs or vim.lsp.buf.type_definition, "go to type definition")
					map("gD", vim.lsp.buf.declaration, "go to declaration")
					map("K", vim.lsp.buf.hover, "hover documentation")
					map("<C-k>", vim.lsp.buf.signature_help, "signature help", "i")
					map("<leader>rn", vim.lsp.buf.rename, "rename symbol")
					map("<leader>ca", vim.lsp.buf.code_action, "code action", { "n", "v" })
					map("<leader>ds", ok and fzf.lsp_document_symbols or vim.lsp.buf.document_symbol, "document symbols")
					map("<leader>ws", ok and fzf.lsp_live_workspace_symbols or vim.lsp.buf.workspace_symbol, "workspace symbols")
					map("[d", function() vim.diagnostic.jump({ count = -1 }) end, "previous diagnostic")
					map("]d", function() vim.diagnostic.jump({ count = 1 }) end, "next diagnostic")

					-- Highlight every occurrence of the symbol under the
					-- cursor, cleared as soon as the cursor moves off it.
					local client = vim.lsp.get_client_by_id(event.data.client_id)
					if client and client:supports_method("textDocument/documentHighlight") then
						local hl_group = vim.api.nvim_create_augroup("lsp_document_highlight", { clear = false })
						vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
							buffer = event.buf,
							group = hl_group,
							callback = vim.lsp.buf.document_highlight,
						})
						vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
							buffer = event.buf,
							group = hl_group,
							callback = vim.lsp.buf.clear_references,
						})
					end

					-- Inlay hints (parameter names, inferred types). Toggled
					-- rather than always on: they are useful while reading
					-- unfamiliar code and noisy while writing.
					if client and client:supports_method("textDocument/inlayHint") then
						map("<leader>th", function()
							vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled({ bufnr = event.buf }), { bufnr = event.buf })
						end, "toggle inlay hints")
					end
				end,
			})
		end,
	},

	-- Autocompletion
	{
		"hrsh7th/nvim-cmp",
		lazy = false,
		version = false,
		dependencies = {
			"hrsh7th/cmp-nvim-lsp",
			"hrsh7th/cmp-buffer",
			"hrsh7th/cmp-path",
			"hrsh7th/cmp-nvim-lsp-signature-help",
			"L3MON4D3/LuaSnip",
			"saadparwaiz1/cmp_luasnip",
			"rafamadriz/friendly-snippets",
		},
		config = function()
			local cmp = require("cmp")
			local luasnip = require("luasnip")

			require("luasnip.loaders.from_vscode").lazy_load()

			cmp.setup({
				snippet = {
					expand = function(args)
						luasnip.lsp_expand(args.body)
					end,
				},
				mapping = cmp.mapping.preset.insert({
					["<C-k>"] = cmp.mapping.select_prev_item(),
					["<C-j>"] = cmp.mapping.select_next_item(),
					["<C-Space>"] = cmp.mapping.complete(),
					["<CR>"] = cmp.mapping.confirm({ select = true }),
					["<Tab>"] = cmp.mapping(function(fallback)
						if cmp.visible() then
							cmp.select_next_item()
						elseif luasnip.expand_or_jumpable() then
							luasnip.expand_or_jump()
						else
							fallback()
						end
					end, { "i", "s" }),
					["<S-Tab>"] = cmp.mapping(function(fallback)
						if cmp.visible() then
							cmp.select_prev_item()
						elseif luasnip.jumpable(-1) then
							luasnip.jump(-1)
						else
							fallback()
						end
					end, { "i", "s" }),
				}),
				sources = cmp.config.sources({
					{ name = "nvim_lsp" },
					{ name = "luasnip" },
					{ name = "buffer" },
					{ name = "path" },
				}),
			})
		end,
	},

	-- Snippets
	{
		"L3MON4D3/LuaSnip",
		version = "v2.*",
		build = "make install_jsregexp",
		config = function()
			local ls = require("luasnip")

			vim.keymap.set({ "i" }, "<C-K>", function()
				ls.expand()
			end, { silent = true })
			vim.keymap.set({ "i", "s" }, "<C-L>", function()
				ls.jump(1)
			end, { silent = true })
			vim.keymap.set({ "i", "s" }, "<C-J>", function()
				ls.jump(-1)
			end, { silent = true })
			vim.keymap.set({ "i", "s" }, "<C-E>", function()
				if ls.choice_active() then
					ls.change_choice(1)
				end
			end, { silent = true })
		end,
	},

	-- Trouble (diagnostics UI)
	{
		"folke/lsp-trouble.nvim",
		config = function()
			require("trouble").setup({
				icons = true,
				use_diagnostic_signs = true,
			})
		end,
	},
}
