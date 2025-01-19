return {
  {
    "echasnovski/mini.nvim",
    config = function()
      require('mini.ai').setup()
      require('mini.bracketed').setup()
      require('mini.comment').setup()
      require('mini.completion').setup({
        window = {
          info = { height = 25, width = 80, border = 'solid' },
          signature = { height = 25, width = 80, border = 'solid' },
        }
      })
      require('mini.diff').setup()
      require('mini.git').setup()
      require('mini.icons').setup()
      require('mini.indentscope').setup()
      require('mini.notify').setup()
      require('mini.pick').setup()
      require('mini.splitjoin').setup()
      require('mini.starter').setup()
      require("mini.statusline").setup { use_icons = true }
      require('mini.surround').setup()
      require('mini.tabline').setup()
      require('mini.trailspace').setup()
    end
  }
}
