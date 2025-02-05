return {
  {
    'stevearc/oil.nvim',
    opts = {},
    dependencies = { { "echasnovski/mini.icons", opts = {} } },
    config = function()
      require("oil").setup({
        default_file_explorer = false,
        use_default_keymaps = true,
        view_options = {
          show_hidden = true,
        },
      })
    end
  }
}
