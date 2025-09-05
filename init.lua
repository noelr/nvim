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
      opts = {
        delay = 500,
      }
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
        { "<leader>fs", "<cmd>Telescope git_status<cr>", desc = "Git status" },
        { "<leader>fn", function() require('telescope.builtin').find_files({ cwd = vim.fn.stdpath('config') }) end, desc = "Neovim config" },
        { "<C-p>", function() require('command-palette').command_palette() end, desc = "Command palette" },
      },
      config = function()
        require('command-palette').setup()
      end,
    },
    { "nvim-treesitter/nvim-treesitter", build = ":TSUpdate" },
    { "neovim/nvim-lspconfig",
      config = function()
        -- vim.lsp.enable('csharp-ls')
        -- vim.lsp.enable('fsautocomplete')
        -- vim.lsp.enable('flow')
        vim.lsp.enable('html')
        vim.lsp.enable('lua_ls')
        vim.lsp.enable('ocamllsp')
        vim.lsp.enable('omnisharp')
        vim.lsp.enable('solargraph')
        vim.lsp.config('ts_ls', {
          filetypes = { "typescript", "typescriptreact" },
        })
        vim.lsp.enable('ts_ls')
      end
    },
    { "mason-org/mason.nvim",
      opts = {},
    },
    { "noelr/floating-cmdline.nvim",
      config = function()
        require('floating-cmdline').setup()
      end,
    },
  },
  -- Configure any other settings here. See the documentation for more details.
  -- colorscheme that will be used when installing plugins.
  -- install = { colorscheme = { "habamax" } },
  -- automatically check for plugin updates
  -- checker = { enabled = true },
})

