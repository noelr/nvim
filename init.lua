vim.o.wrap = false
vim.keymap.set("n", "<c-c>", ":nohlsearch<cr>", { silent = true })
vim.keymap.set("i", "<c-c>", "<esc>", { silent = true })
vim.o.number = true
vim.cmd([[set signcolumn=number]])
vim.o.ignorecase = true
vim.o.smartcase = true
vim.o.incsearch = true
vim.o.scrolloff = 5
vim.o.winwidth = 120

vim.diagnostic.config({
  -- virtual_lines = true,
  virtual_text = { current_line = true }
})

vim.pack.add({
  { src = "https://github.com/tpope/vim-rails" },
  { src = "https://github.com/folke/tokyonight.nvim" },
  { src = "https://github.com/nvim-lua/plenary.nvim" },
  { src = "https://github.com/nvim-telescope/telescope.nvim" },
  { src = "https://github.com/nvim-treesitter/nvim-treesitter" },
  { src = "https://github.com/neovim/nvim-lspconfig" },
  { src = "https://github.com/mason-org/mason.nvim" },
})

vim.cmd([[colorscheme tokyonight-moon]])

require("mason").setup()

vim.lsp.enable('html')
vim.lsp.enable('lua_ls')
vim.lsp.enable('ocamllsp')
vim.lsp.enable('omnisharp')
vim.lsp.enable('solargraph')
vim.lsp.config('ts_ls', {
  filetypes = { "typescript", "typescriptreact" },
})
vim.lsp.enable('ts_ls')

vim.keymap.set("n", "<leader>ff", "<cmd>Telescope find_files<cr>", { desc = "Find files" })
vim.keymap.set("n", "<leader>fg", "<cmd>Telescope live_grep<cr>", { desc = "Live grep" })
vim.keymap.set("n", "<leader>fb", "<cmd>Telescope buffers<cr>", { desc = "Buffers" })
vim.keymap.set("n", "<leader>fh", "<cmd>Telescope help_tags<cr>", { desc = "Help tags" })
vim.keymap.set("n", "<leader>fs", "<cmd>Telescope git_status<cr>", { desc = "Git status" })
vim.keymap.set("n", "<leader>fn", function()
  require('telescope.builtin').find_files({ cwd = vim.fn.stdpath('config') })
end, { desc = "Neovim config" })
