vim.o.wrap = false
-- The built-in sql ftplugin maps <C-C>{a,k,t,c,...} for omni-completion, which
-- shadows <c-c> and makes it wait timeoutlen. Move that trigger off <C-C>.
vim.g.ftplugin_sql_omni_key = "<C-J>"
vim.keymap.set("n", "<c-c>", ":nohlsearch<cr>", { silent = true })
vim.keymap.set("i", "<c-c>", "<esc>", { silent = true })
vim.o.number = true
vim.cmd([[set signcolumn=number]])
vim.o.ignorecase = true
vim.o.smartcase = true
vim.o.incsearch = true
vim.o.scrolloff = 5
vim.o.winwidth = 120

-- require('vim._core.ui2').enable()
vim.opt.runtimepath:prepend("/Users/noel/devel/inline")

vim.diagnostic.config({
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
  { src = "https://github.com/nvim-lua/plenary.nvim" },
  { src = "https://github.com/folke/snacks.nvim" },
  { src = "https://github.com/GustavEikaas/easy-dotnet.nvim" },
  { src = "https://codeberg.org/mfussenegger/nvim-dap.git" },
})

vim.cmd([[colorscheme tokyonight-moon]])

require("easy-dotnet").setup({
  debugger = {
    -- netcoredbg fork with better funceval; sharpdbg loses the stopped
    -- state on REPL assignments (as of easydotnet 3.4.11)
    engine = "dncdbg",
  },
})
-- inline variable values + `T` variable viewer while stopped at a breakpoint
require("easy-dotnet.netcoredbg").register_dap_variables_viewer()
require("mason").setup()

vim.lsp.enable('html')
vim.lsp.enable('lua_ls')
vim.lsp.enable('ocamllsp')
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
