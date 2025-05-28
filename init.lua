vim.o.wrap = false
vim.keymap.set("n", "<c-c>", ":nohlsearch<cr>", { silent = true })
vim.keymap.set("i", "<c-c>", "<esc>", { silent = true })

-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\nPress any key to exit..." },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)

-- Make sure to setup `mapleader` and `maplocalleader` before
-- loading lazy.nvim so that mappings are correct.
-- This is also a good place to setup other settings (vim.opt)
-- vim.g.mapleader = " "
-- vim.g.maplocalleader = "\\"

-- Setup lazy.nvim
require("lazy").setup({
  spec = {
    { "github/copilot.vim" },
    { "tpope/vim-rails" },
    { "folke/lazy.nvim" },
    { "folke/which-key.nvim", lazy = false,
      dependencies = { "nvim-tree/nvim-web-devicons", "echasnovski/mini.icons" },
    },
    { "folke/tokyonight.nvim", config = function()
      vim.cmd([[colorscheme tokyonight-moon]])
    end},
    { "nvim-lua/telescope.nvim",
      dependencies = { "nvim-lua/plenary.nvim" },
      cmd = "Telescope",
      keys = {
        { "<leader>ff", "<cmd>Telescope find_files<cr>", desc = "Find files" },
        { "<leader>fg", "<cmd>Telescope live_grep<cr>", desc = "Live grep" },
        { "<leader>fb", "<cmd>Telescope buffers<cr>", desc = "Buffers" },
        { "<leader>fh", "<cmd>Telescope help_tags<cr>", desc = "Help tags" },
        { "<leader>fn", function() require('telescope.builtin').find_files({ cwd = vim.fn.stdpath('config') }) end, desc = "Neovim config" },
      },
    },
    { "nvim-treesitter/nvim-treesitter", build = ":TSUpdate" },
    { "neovim/nvim-lspconfig",
      config = function()
        vim.lsp.enable('csharp-language-server')
        vim.lsp.enable('fsautocomplete')
        vim.lsp.enable('haml-lint')
        vim.lsp.enable('html-lsp')
        vim.lsp.enable('lua-language-server')
        vim.lsp.enable('ocaml-lsp')
        vim.lsp.enable('omnisharp')
        vim.lsp.enable('solargraph')
        vim.lsp.enable('typescript-language-server')
      end
    },
    { "mason-org/mason.nvim",
      opts = {},
    },
  },
  -- Configure any other settings here. See the documentation for more details.
  -- colorscheme that will be used when installing plugins.
  -- install = { colorscheme = { "habamax" } },
  -- automatically check for plugin updates
  -- checker = { enabled = true },
})
