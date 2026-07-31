local opt = vim.opt
local cmd = vim.cmd
local g = vim.g
local o = vim.o

-- automatically indent when entering a new line
opt.autoindent = true

-- window-scoped
opt.cursorline = true

-- global scope
opt.autowrite = true

-- Set the behavior of tab
opt.tabstop = 2
opt.shiftwidth = 4
opt.softtabstop = 2
opt.number = true
opt.fillchars = { eob = " " }  -- This will replace the tilde with a blank space

opt.cursorline = true

-- Prettier config
g.lazyvim_prettier_needs_config = false

o.termguicolors = true
o.wrap = false

-- Global variable that sets the current theme globally
g.currentTheme = "vscode"

-- Add diagnostics

vim.diagnostic.config({
  virtual_text = true,         -- show inline errors
  update_in_insert = true,     -- update diagnostics in insert mode
  severity_sort = true,        -- sort by severity
  float = {
    source = "always",         -- show the source in the floating popup
  },
})
vim.o.updatetime = 250
