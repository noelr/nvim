return {
  { "williamboman/mason.nvim", config = true },
  {
    "williamboman/mason-lspconfig.nvim",
    config = function()
      require("mason").setup()
    end
  },
  {
    "folke/lazydev.nvim",
    opts = {
      library = {
        { path = "luvit-meta/library", words = { "vim%.uv" } },
      },
    },
  },
  {
    "neovim/nvim-lspconfig",
    config = function()
      local lspconfig = require 'lspconfig'
      local servers = {
        { name = "lua_ls",     setup = {} },
        { name = "solargraph", setup = {} },
        { name = "sourcekit",  setup = {} },
        { name = "html",       setup = {} },
        { name = "cssls",      setup = {} },
        { name = "ts_ls",      setup = {} },
        { name = "ocamllsp",      setup = {} },
        { name = "omnisharp",  setup = { cmd = { 'omnisharp' } } },
      }

      for _, server in ipairs(servers) do
        lspconfig[server.name].setup(server.setup)
      end

      vim.keymap.set("n", "gff", function() vim.lsp.buf.format() end)
      vim.keymap.set('n', 'gds', vim.lsp.buf.document_symbol)
      vim.keymap.set('n', 'gci', vim.lsp.buf.implementation)
      local version = vim.version()
      if version.major > 0 or (version.major == 0 and version.minor >= 11) then
      else
        vim.keymap.set('n', 'grn', vim.lsp.buf.rename)
        vim.keymap.set('n', 'gra', vim.lsp.buf.code_action)
        vim.keymap.set('n', 'grr', vim.lsp.buf.references)
      end
    end
  }
}
