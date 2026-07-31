vim.api.nvim_create_autocmd({"BufEnter"}, {
	group = vim.api.nvim_create_augroup("Neotree_start_directory", { clear = true }),
	desc = "Start Neo-tree with directory or file",
	once = true,
	callback = function()
		if package.loaded["neo-tree"] then
			return
		else
			local stats = vim.uv.fs_stat(vim.fn.argv(0))
			if stats then
				if stats.type == "directory" then
					require("neo-tree")
				end
			end
		end
	end
})

vim.api.nvim_create_autocmd("CursorHold", {
  callback = function()
    vim.diagnostic.open_float(nil, { focusable = false })
  end,
})
