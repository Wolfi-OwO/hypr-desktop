-- Debug Adapter Protocol.
--
-- This config had no debugger at all before: breakpoints meant print statements
-- and re-running the process by hand. nvim-dap speaks the same protocol VS Code
-- uses, so the adapters below are the same binaries VS Code would download --
-- Mason just puts them somewhere Neovim can find them.
--
-- Keys follow the IDE convention rather than Vim's, because that is what muscle
-- memory already knows from every other debugger:
--   F5   continue / start        F9   toggle breakpoint
--   F10  step over               F11  step into        F12  step out
-- Everything else lives under <leader>d.

return {
	{
		"mfussenegger/nvim-dap",
		dependencies = {
			"rcarriga/nvim-dap-ui",
			"nvim-neotest/nvim-nio", -- hard requirement of dap-ui since v3
			"theHamsta/nvim-dap-virtual-text",
			"jay-babu/mason-nvim-dap.nvim",
			"williamboman/mason.nvim",
		},

		-- Loaded on the keys rather than at startup: the adapter definitions
		-- below are cheap, but dap-ui pulls in nio and builds its windows, and
		-- none of that is needed to open a file.
		keys = {
			{ "<F5>", function() require("dap").continue() end, desc = "Debug: start / continue" },
			{ "<F9>", function() require("dap").toggle_breakpoint() end, desc = "Debug: toggle breakpoint" },
			{ "<F10>", function() require("dap").step_over() end, desc = "Debug: step over" },
			{ "<F11>", function() require("dap").step_into() end, desc = "Debug: step into" },
			{ "<F12>", function() require("dap").step_out() end, desc = "Debug: step out" },

			{ "<leader>db", function() require("dap").toggle_breakpoint() end, desc = "Toggle breakpoint" },
			{
				"<leader>dB",
				function()
					vim.ui.input({ prompt = "Breakpoint condition: " }, function(cond)
						if cond and cond ~= "" then
							require("dap").set_breakpoint(cond)
						end
					end)
				end,
				desc = "Conditional breakpoint",
			},
			{
				"<leader>dL",
				function()
					vim.ui.input({ prompt = "Log point message: " }, function(msg)
						if msg and msg ~= "" then
							require("dap").set_breakpoint(nil, nil, msg)
						end
					end)
				end,
				desc = "Log point",
			},
			{ "<leader>dc", function() require("dap").continue() end, desc = "Continue" },
			{ "<leader>dC", function() require("dap").run_to_cursor() end, desc = "Run to cursor" },
			{ "<leader>dr", function() require("dap").restart() end, desc = "Restart session" },
			{ "<leader>dt", function() require("dap").terminate() end, desc = "Terminate session" },
			{ "<leader>dl", function() require("dap").run_last() end, desc = "Re-run last configuration" },
			{ "<leader>du", function() require("dapui").toggle() end, desc = "Toggle debugger UI" },
			{
				"<leader>de",
				function() require("dapui").eval(nil, { enter = true }) end,
				mode = { "n", "v" },
				desc = "Evaluate expression",
			},
			{ "<leader>dR", function() require("dap").repl.toggle() end, desc = "Toggle REPL" },
			{
				"<leader>dx",
				function()
					require("dap").clear_breakpoints()
					vim.notify("All breakpoints cleared", vim.log.levels.INFO)
				end,
				desc = "Clear all breakpoints",
			},
		},

		config = function()
			local dap = require("dap")
			local dapui = require("dapui")

			-- ---------------------------------------------------------------
			--  Signs
			-- ---------------------------------------------------------------
			-- The defaults are the letter "B" in the number column, which is
			-- easy to miss next to line numbers. These use the same Nerd Font
			-- glyphs as the rest of the setup.
			local signs = {
				DapBreakpoint = { text = "", texthl = "DiagnosticSignError" },
				DapBreakpointCondition = { text = "", texthl = "DiagnosticSignWarn" },
				DapLogPoint = { text = "", texthl = "DiagnosticSignInfo" },
				DapStopped = { text = "", texthl = "DiagnosticSignWarn", linehl = "DapStoppedLine" },
				DapBreakpointRejected = { text = "", texthl = "DiagnosticSignError" },
			}
			for name, opts in pairs(signs) do
				vim.fn.sign_define(name, opts)
			end
			-- Highlight the line execution is stopped on. Derived from Visual so
			-- it follows whichever colour scheme themery has selected.
			vim.api.nvim_set_hl(0, "DapStoppedLine", { link = "Visual", default = true })

			-- ---------------------------------------------------------------
			--  UI
			-- ---------------------------------------------------------------
			dapui.setup({
				icons = { expanded = "", collapsed = "", current_frame = "" },
				layouts = {
					{
						elements = {
							{ id = "scopes", size = 0.35 },
							{ id = "breakpoints", size = 0.15 },
							{ id = "stacks", size = 0.25 },
							{ id = "watches", size = 0.25 },
						},
						size = 46,
						position = "left",
					},
					{
						elements = {
							{ id = "repl", size = 0.5 },
							{ id = "console", size = 0.5 },
						},
						size = 0.28,
						position = "bottom",
					},
				},
				floating = { border = "rounded" },
			})

			-- Open the UI when a session starts, close it when it ends. Without
			-- this the windows have to be toggled by hand every single run.
			dap.listeners.after.event_initialized["dapui_config"] = function()
				dapui.open()
			end
			dap.listeners.before.event_terminated["dapui_config"] = function()
				dapui.close()
			end
			dap.listeners.before.event_exited["dapui_config"] = function()
				dapui.close()
			end

			require("nvim-dap-virtual-text").setup({
				commented = true, -- render as a comment so it cannot be confused with code
				virt_text_pos = "eol",
			})

			-- ---------------------------------------------------------------
			--  Adapters installed through Mason
			-- ---------------------------------------------------------------
			-- mason-nvim-dap writes the adapter definitions for anything listed
			-- here, so the paths stay correct when Mason updates a package.
			-- handlers = {} would disable that; the default handler is kept and
			-- only the two that need real configuration are overridden.
			require("mason-nvim-dap").setup({
				ensure_installed = {
					"python", -- debugpy
					"js", -- js-debug-adapter, for Node and TypeScript
					"delve", -- Go
					"codelldb", -- C, C++, Rust
				},
				automatic_installation = true,
				handlers = {
					function(cfg)
						require("mason-nvim-dap").default_setup(cfg)
					end,

					python = function(cfg)
						-- Prefer the interpreter of an activated virtualenv, so
						-- the debugger imports the same packages the code does.
						-- Falls back to the system interpreter outside a venv.
						cfg.adapters = {
							type = "executable",
							command = vim.fn.exepath("python3"),
							args = { "-m", "debugpy.adapter" },
						}
						cfg.configurations = {
							{
								type = "python",
								request = "launch",
								name = "Launch current file",
								program = "${file}",
								console = "integratedTerminal",
								justMyCode = false, -- step into library code too
								pythonPath = function()
									local venv = os.getenv("VIRTUAL_ENV") or os.getenv("CONDA_PREFIX")
									if venv then
										return venv .. "/bin/python"
									end
									return vim.fn.exepath("python3")
								end,
							},
							{
								type = "python",
								request = "attach",
								name = "Attach to running process (port 5678)",
								connect = { host = "127.0.0.1", port = 5678 },
							},
						}
						require("mason-nvim-dap").default_setup(cfg)
					end,
				},
			})

			-- ---------------------------------------------------------------
			--  JavaScript / TypeScript
			-- ---------------------------------------------------------------
			-- The adapter is defined here rather than left to mason-nvim-dap.
			-- Its "js" handler did not register pwa-node even with
			-- js-debug-adapter installed -- verified by inspecting
			-- dap.adapters, which listed only debugpy, python and delve -- so
			-- every JS and TS launch failed with "adapter pwa-node not found".
			-- Pointing at the Mason binary directly removes that dependency.
			dap.adapters["pwa-node"] = {
				type = "server",
				host = "localhost",
				-- ${port} is substituted by nvim-dap with a free port, so
				-- several debug sessions can run side by side.
				port = "${port}",
				executable = {
					command = vim.fn.stdpath("data") .. "/mason/bin/js-debug-adapter",
					args = { "${port}" },
				},
			}

			-- These are the launch configurations that use it.
			for _, lang in ipairs({ "javascript", "typescript", "javascriptreact", "typescriptreact" }) do
				dap.configurations[lang] = {
					{
						type = "pwa-node",
						request = "launch",
						name = "Launch current file",
						program = "${file}",
						cwd = "${workspaceFolder}",
						runtimeExecutable = "node",
						sourceMaps = true,
						-- ts-node so a .ts file runs without a build step.
						runtimeArgs = { "--enable-source-maps" },
						skipFiles = { "<node_internals>/**", "node_modules/**" },
					},
					{
						type = "pwa-node",
						request = "attach",
						name = "Attach to process",
						processId = require("dap.utils").pick_process,
						cwd = "${workspaceFolder}",
						sourceMaps = true,
						skipFiles = { "<node_internals>/**", "node_modules/**" },
					},
					{
						type = "pwa-node",
						request = "launch",
						name = "Debug npm script",
						runtimeExecutable = "npm",
						runtimeArgs = { "run-script", "dev" },
						cwd = "${workspaceFolder}",
						console = "integratedTerminal",
						skipFiles = { "<node_internals>/**", "node_modules/**" },
					},
				}
			end

			-- ---------------------------------------------------------------
			--  Launch configurations from .vscode/launch.json
			-- ---------------------------------------------------------------
			-- Projects that already ship a VS Code debug setup work without
			-- duplicating it here. The map translates VS Code's adapter names
			-- to the filetypes nvim-dap should offer them for.
			require("dap.ext.vscode").load_launchjs(nil, {
				["pwa-node"] = { "javascript", "typescript", "javascriptreact", "typescriptreact" },
				["node"] = { "javascript", "typescript" },
				["python"] = { "python" },
				["java"] = { "java" },
				["go"] = { "go" },
				["codelldb"] = { "c", "cpp", "rust" },
			})
		end,
	},

	-- Python gets its own module because test-level debugging (debug the test
	-- under the cursor) needs to know about pytest/unittest, which generic dap
	-- configurations cannot infer.
	{
		"mfussenegger/nvim-dap-python",
		ft = "python",
		dependencies = { "mfussenegger/nvim-dap" },
		config = function()
			local mason_python = vim.fn.stdpath("data") .. "/mason/packages/debugpy/venv/bin/python"
			-- Fall back to the system interpreter if Mason has not installed
			-- debugpy yet, so the first launch reports a clear error instead of
			-- failing on a missing path.
			require("dap-python").setup(vim.uv.fs_stat(mason_python) and mason_python or "python3")
		end,
		keys = {
			{
				"<leader>dm",
				function() require("dap-python").test_method() end,
				desc = "Debug test method under cursor",
				ft = "python",
			},
			{
				"<leader>dM",
				function() require("dap-python").test_class() end,
				desc = "Debug test class",
				ft = "python",
			},
		},
	},
}
