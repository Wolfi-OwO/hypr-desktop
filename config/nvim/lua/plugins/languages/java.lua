-- Java through nvim-jdtls.
--
-- Java is the one language that cannot go through nvim-lspconfig here. jdtls
-- keeps a persistent workspace directory per project (indexes, build state),
-- needs the launcher jar passed on the command line, and loads debugging and
-- test support as separate OSGi bundles. nvim-jdtls exists to do exactly that,
-- and starting the same server twice -- once by lspconfig, once by jdtls --
-- corrupts the workspace, which is why "jdtls" is deliberately absent from the
-- mason-lspconfig list in lsp-config.lua.

return {
	{
		"mfussenegger/nvim-jdtls",
		ft = { "java" },
		dependencies = { "mfussenegger/nvim-dap" },
		config = function()
			local jdtls_ok, jdtls = pcall(require, "jdtls")
			if not jdtls_ok then
				return
			end

			local mason = vim.fn.stdpath("data") .. "/mason"
			local jdtls_path = mason .. "/packages/jdtls"

			-- Every project gets its own workspace. Sharing one across projects
			-- makes jdtls re-index on every switch and occasionally resolve
			-- symbols against the wrong source tree.
			local project = vim.fn.fnamemodify(vim.fn.getcwd(), ":p:h:t")
			local workspace = vim.fn.stdpath("cache") .. "/jdtls-workspace/" .. project

			-- The config directory is platform-specific and ships inside the
			-- Mason package.
			local config_dir = jdtls_path .. "/config_linux"

			-- The launcher jar carries a version in its filename, so it has to
			-- be globbed rather than hard-coded -- a Mason update would
			-- otherwise silently break the whole setup.
			local launcher = vim.fn.glob(jdtls_path .. "/plugins/org.eclipse.equinox.launcher_*.jar")

			if launcher == "" then
				vim.notify(
					"jdtls is not installed. Run :MasonInstall jdtls java-debug-adapter java-test",
					vim.log.levels.WARN
				)
				return
			end

			-- Debugging and test running are separate bundles. Without them
			-- nvim-dap has no Java adapter at all and <leader>dc does nothing
			-- in a .java buffer.
			local bundles = {}
			vim.list_extend(
				bundles,
				vim.split(
					vim.fn.glob(mason .. "/packages/java-debug-adapter/extension/server/com.microsoft.java.debug.plugin-*.jar", true),
					"\n"
				)
			)
			vim.list_extend(
				bundles,
				vim.split(vim.fn.glob(mason .. "/packages/java-test/extension/server/*.jar", true), "\n")
			)
			-- glob() returns a list containing one empty string when nothing
			-- matched; passing that to jdtls makes it fail to start.
			bundles = vim.tbl_filter(function(j)
				return j ~= ""
			end, bundles)

			-- jdtls itself must run on Java 21 or newer. This machine's default
			-- is java-17-openjdk (archlinux-java status), and on 17 the server
			-- dies during OSGi startup with a bare "An error has occurred" --
			-- which reaches Neovim as nothing at all: no client attaches, no
			-- message, no log. That is why the runtime is resolved explicitly
			-- here instead of using whatever `java` is on PATH.
			--
			-- The system default is deliberately left alone: projects on this
			-- machine compile against 17, and `archlinux-java set` would change
			-- that for every tool at once. Only the language server moves to 21.
			local function jdtls_runtime()
				local candidates = {
					"/usr/lib/jvm/java-25-openjdk",
					"/usr/lib/jvm/java-24-openjdk",
					"/usr/lib/jvm/java-23-openjdk",
					"/usr/lib/jvm/java-22-openjdk",
					"/usr/lib/jvm/java-21-openjdk",
				}
				-- Inserted rather than written as the first list element:
				-- os.getenv returns nil when the variable is unset, and a nil
				-- at index 1 makes ipairs stop before it starts, so the whole
				-- search silently fell through to the "java" fallback.
				local override = os.getenv("JDTLS_JAVA_HOME")
				if override then
					table.insert(candidates, 1, override)
				end

				for _, candidate in ipairs(candidates) do
					if vim.uv.fs_stat(candidate .. "/bin/java") then
						return candidate .. "/bin/java"
					end
				end
				vim.notify(
					"No JDK 21+ found for jdtls; falling back to the default java, "
						.. "which will fail if it is older than 21. "
						.. "Install one with: sudo pacman -S jdk21-openjdk",
					vim.log.levels.WARN
				)
				return "java"
			end

			local config = {
				cmd = {
					jdtls_runtime(),
					"-Declipse.application=org.eclipse.jdt.ls.core.id1",
					"-Dosgi.bundles.defaultStartLevel=4",
					"-Declipse.product=org.eclipse.jdt.ls.core.product",
					"-Dlog.protocol=true",
					"-Dlog.level=ALL",
					"-Xmx2g",
					"--add-modules=ALL-SYSTEM",
					"--add-opens", "java.base/java.util=ALL-UNNAMED",
					"--add-opens", "java.base/java.lang=ALL-UNNAMED",
					"-jar", launcher,
					"-configuration", config_dir,
					"-data", workspace,
				},

				-- Marker files, most specific first. Gradle and Maven projects
				-- are detected by their build file; a bare git repository is the
				-- fallback so single-file experiments still get a server.
				root_dir = vim.fs.root(0, { "gradlew", "mvnw", "pom.xml", "build.gradle", "build.gradle.kts", ".git" }),

				settings = {
					java = {
						-- The server runs on 21 (see jdtls_runtime above), but
						-- the code it analyses does not have to. Every JDK
						-- installed here is offered, so a project targeting 17
						-- is still checked against the 17 class library rather
						-- than against whatever the server happens to run on.
						configuration = {
							runtimes = (function()
								local runtimes = {}
								local known = {
									["java-17-openjdk"] = "JavaSE-17",
									["java-21-openjdk"] = "JavaSE-21",
									["java-22-openjdk"] = "JavaSE-22",
									["java-23-openjdk"] = "JavaSE-23",
									["java-24-openjdk"] = "JavaSE-24",
									["java-25-openjdk"] = "JavaSE-25",
								}
								for dir, name in pairs(known) do
									local path = "/usr/lib/jvm/" .. dir
									if vim.uv.fs_stat(path .. "/bin/java") then
										table.insert(runtimes, { name = name, path = path })
									end
								end
								return runtimes
							end)(),
						},
						eclipse = { downloadSources = true },
						maven = { downloadSources = true },
						implementationsCodeLens = { enabled = true },
						referencesCodeLens = { enabled = true },
						references = { includeDecompiledSources = true },
						signatureHelp = { enabled = true },
						format = { enabled = true },
						-- Suggest imports for these even before they appear in
						-- the project's dependencies.
						completion = {
							favoriteStaticMembers = {
								"org.junit.jupiter.api.Assertions.*",
								"org.junit.Assert.*",
								"org.mockito.Mockito.*",
								"java.util.Objects.requireNonNull",
							},
							importOrder = { "java", "javax", "com", "org" },
						},
						sources = {
							organizeImports = {
								-- Below these counts jdtls writes explicit
								-- imports rather than a wildcard.
								starThreshold = 9999,
								staticStarThreshold = 9999,
							},
						},
					},
				},

				init_options = { bundles = bundles },

				capabilities = (function()
					local ok, cmp_lsp = pcall(require, "cmp_nvim_lsp")
					return ok and cmp_lsp.default_capabilities() or vim.lsp.protocol.make_client_capabilities()
				end)(),

				on_attach = function(_, bufnr)
					-- Wires the Java debug adapter into nvim-dap. Must run after
					-- the server is up, because the bundle registers a command
					-- on the server side.
					pcall(jdtls.setup_dap, { hotcodereplace = "auto" })
					pcall(function()
						require("jdtls.dap").setup_dap_main_class_configs()
					end)

					local map = function(keys, fn, desc)
						vim.keymap.set("n", keys, fn, { buffer = bufnr, desc = "Java: " .. desc })
					end
					map("<leader>jo", jdtls.organize_imports, "organize imports")
					map("<leader>jv", jdtls.extract_variable, "extract variable")
					map("<leader>jc", jdtls.extract_constant, "extract constant")
					map("<leader>jm", function()
						jdtls.extract_method(true)
					end, "extract method")
					map("<leader>jt", jdtls.test_nearest_method, "test method under cursor")
					map("<leader>jT", jdtls.test_class, "test class")
				end,
			}

			-- ft = "java" means this file is sourced when the first Java buffer
			-- opens, and that buffer needs the server too -- so start once here
			-- and once per subsequent FileType event.
			jdtls.start_or_attach(config)
			vim.api.nvim_create_autocmd("FileType", {
				group = vim.api.nvim_create_augroup("jdtls_attach", { clear = true }),
				pattern = "java",
				callback = function()
					jdtls.start_or_attach(config)
				end,
			})
		end,
	},
}
