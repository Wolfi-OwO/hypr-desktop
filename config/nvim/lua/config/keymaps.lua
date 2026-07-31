vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

vim.api.nvim_set_keymap('t','<ESC>','<C-\\><C-n>',{noremap = true})

vim.api.nvim_set_keymap("n", "<Tab>", "<Cmd>BufferLineCycleNext<CR>", { silent = true })
vim.api.nvim_set_keymap("n", "<S-Tab>", "<Cmd>BufferLineCyclePrev<CR>", { silent = true })
