local M = {
	currentTheme = "auto",
}

M.getIcon = function(file, icon_type)
	local devicons = require("nvim-web-devicons")
	local icon, hl = devicons.get_icon(file, nil, { default = true })

	return { icon or "", width = 2, hl = hl or "Normal" }
end

M.getRootProjectDir = function()
	local filepath = vim.fn.expand("%:p")
	if filepath == "" then
		return nil
	end

	local dir = vim.fn.fnamemodify(filepath, ":h")
	local git_cmd = "git -C " .. vim.fn.fnameescape(dir) .. " rev-parse --show-toplevel"
	local result = vim.fn.systemlist(git_cmd)

	if vim.v.shell_error == 0 and result[1] ~= "" then
		return result[1]
	else
		return nil
	end
end

M.getCurrentTheme = function()
	return M.currentTheme
end

M.setCurrentTheme = function(themeName)
	M.currentTheme = themeName
end

return M
