local M = {}

local state = {
  floating = {
    buf = -1,
    win = -1
  }
}

local create_floating_window = function(bufnr, opts)
  -- Default options for width and height
  opts = opts or {}
  local width = opts.width or math.floor(vim.o.columns * 0.8)   -- 80% of screen width
  local height = opts.height or math.floor(vim.o.lines * 0.8)   -- 80% of screen height

  -- Get the screen dimensions (columns and lines)
  local screen_width = vim.o.columns
  local screen_height = vim.o.lines

  -- Calculate the position to center the window
  local row = math.floor((screen_height - height) / 2)
  local col = math.floor((screen_width - width) / 2)

  -- Create the floating window
  local win = vim.api.nvim_open_win(bufnr, true, {
    relative = 'editor',   -- relative to the entire screen (editor)
    width = width,         -- width of the window
    height = height,       -- height of the window
    row = row,             -- top-left position row
    col = col,             -- top-left position column
    style = 'minimal',     -- minimal UI (no borders, etc.)
    border = 'none',       -- optional: add a border, 'none' for no border
  })

  return { buf = bufnr, win = win }
end

M.toggle_terminal = function()
  if not vim.api.nvim_win_is_valid(state.floating.win) then
    -- Create a new buffer
    if not vim.api.nvim_buf_is_valid(state.floating.buf) then
      state.floating.buf = vim.api.nvim_create_buf(false, true)
    end
    state.floating = create_floating_window(state.floating.buf)
    if vim.bo[state.floating.buf].buftype ~= "terminal" then
      vim.cmd.terminal()
    end
  else
    vim.api.nvim_win_hide(state.floating.win)
  end
end

M.setup = function()
  vim.api.nvim_create_user_command("Floaterminal", M.toggle_terminal, {})
  vim.keymap.set({ 'n', 't' }, '<leader>tt', M.toggle_terminal)
end

return M
