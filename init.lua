-- vim.g.mapleader = " "
-- vim.g.maplocalleader = "\\"

vim.o.undofile = false
vim.o.winwidth = 105
vim.o.scrolloff = 5
vim.o.wrap = false
vim.o.undofile = false
vim.o.backup = false
vim.o.number = true
vim.o.termguicolors = true
vim.cmd([[set signcolumn=number]])

-- vim.cmd("set list listchars=tab:»·,trail:·") -- Display extra whitespace. Lua kann » irgendwie nicht
vim.api.nvim_create_autocmd("TermOpen", { command = "setlocal nonumber" })
vim.keymap.set("i", "<c-c>", "<esc>", { silent = true })
vim.keymap.set("n", "<c-c>", "<cmd>:nohlsearch<CR>", { silent = true })
vim.keymap.set("n", "<c-w><space>", "14<c-w>+", { silent = false })
vim.keymap.set("n", "<leader>`", vim.diagnostic.hide)
vim.keymap.set("n", "<leader>~", vim.diagnostic.show)

require("config.lazy")
require("floaterminal").setup()

-- `. go to last insert
