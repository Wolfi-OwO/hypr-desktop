local M = require("utils.GlobalFunctions")
return {
  "nvim-neo-tree/neo-tree.nvim",
	dependencies = {
			"nvim-lua/plenary.nvim",
			"nvim-tree/nvim-web-devicons",
			"MunifTanjim/nui.nvim"
  },
  cmd = "Neotree",

  keys = {
    {
      "<leader>fe",
      function()
        require("neo-tree.command").execute({ toggle = true,
						dir = M.getRootProjectDir() or vim.loop.cwd(),
		  })
      end,
      desc = "Explorer NeoTree (cwd)",
    },
    {
      "<leader>ge",
      function()
        require("neo-tree.command").execute({ source = "git_status", toggle = true })
      end,
      desc = "Git Explorer",
    },
    {
     "<leader>be",
      function()
        require("neo-tree.command").execute({ source = "buffers", toggle = true })
      end,
      desc = "Buffer Explorer",
    },
  },

  deactivate = function()
    vim.cmd([[Neotree close]])
  end,
		window = {
				 mappings = {
							["P"] = {
								"toggle_preview",
								config = {
										use_float = true,
										-- use_image_nvim = true,
										-- title = 'Neo-tree Preview',
								},
						},
				}
		},
		opts = {
			sources = { "filesystem", "buffers", "git_status" },
			open_files_do_not_replace_types = {
				"terminal", "Trouble", "trouble", "qf", "Outline"
			},
			filesystem = {
				bind_to_cwd = false,
				follow_current_file = { enabled = true },
				use_libuv_file_watcher = true, -- <== this enables live file system updates
				filtered_items = {
					visible = false,
					hide_dotfiles = false,
					hide_gitignored = false,
					hide_hidden = false,
				},
				-- auto-refresh on file changes
				hijack_netrw_behavior = "open_default", -- optional: hijack netrw behavior
			},
			buffers = {
				follow_current_file = true,
				group_empty_dirs = true,
				show_unloaded = true,
			},
			git_status = {
				follow_current_file = true,
				show_untracked = true,
				show_ignored = false,
				show_staged = true,
			},
			default_component_configs = {
				git_status = {
					symbols = {
						added     = "✚",
						modified  = "",
						deleted   = "✖",
						renamed   = "󰁕",
						untracked = "",
						ignored   = "",
						unstaged  = "󰄱",
						staged    = "",
						conflict  = "",
					}
				}
			},
			event_handlers = {
				{
					event = "git_event",
					handler = function()
						-- automatically refresh git status view
						require("neo-tree.sources.git_status.commands").refresh()
					end,
				},
				{
					event = "file_renamed",
					handler = function(args)
						-- refresh filesystem when file renamed
						require("neo-tree.sources.filesystem.commands").refresh()
					end,
				},
			},
		}
}
