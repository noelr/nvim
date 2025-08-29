local M = {}

-- Configuration
local config = {
  width_ratio = 0.8,  -- Width relative to screen
  height_ratio = 0.6, -- Height relative to screen
  border = 'rounded', -- Border style
  prompt = '> ',      -- Command prompt
}

-- State
local state = {
  terminal_buf = nil,
  terminal_win = nil,
  is_open = false,
  command_history = {},
  history_index = 0,
  -- Store original context
  original_win = nil,
  original_buf = nil,
}

-- History file
local history_file = vim.fn.stdpath('data') .. '/floating_cmdline_history.json'

-- Load command history
local function load_history()
  local file = io.open(history_file, 'r')
  if file then
    local content = file:read('*a')
    file:close()
    local success, decoded = pcall(vim.json.decode, content)
    if success and decoded and type(decoded) == 'table' then
      state.command_history = decoded
    end
  end
end

-- Save command history
local function save_history()
  local file = io.open(history_file, 'w')
  if file then
    file:write(vim.json.encode(state.command_history))
    file:close()
  end
end

-- Add command to history
local function add_to_history(cmd)
  -- Remove if already exists
  for i, existing in ipairs(state.command_history) do
    if existing == cmd then
      table.remove(state.command_history, i)
      break
    end
  end
  
  -- Add to beginning
  table.insert(state.command_history, 1, cmd)
  
  -- Limit history size
  if #state.command_history > 100 then
    state.command_history[101] = nil
  end
  
  save_history()
end

-- Get window dimensions and position
local function get_window_config()
  local screen_width = vim.o.columns
  local screen_height = vim.o.lines
  
  local width = math.floor(screen_width * config.width_ratio)
  local height = math.floor(screen_height * config.height_ratio)
  
  local col = math.floor((screen_width - width) / 2)
  local row = math.floor((screen_height - height) / 2)
  
  return {
    width = width,
    height = height,
    col = col,
    row = row,
  }
end

-- Create terminal buffer
local function create_terminal_buffer()
  state.terminal_buf = vim.api.nvim_create_buf(false, true)
  
  -- Use neutral filetype to avoid conflicts with netrw and other plugins
  vim.api.nvim_buf_set_option(state.terminal_buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(state.terminal_buf, 'filetype', 'floatingcmd')
  vim.api.nvim_buf_set_option(state.terminal_buf, 'bufhidden', 'wipe')
  vim.api.nvim_buf_set_option(state.terminal_buf, 'swapfile', false)
  vim.api.nvim_buf_set_option(state.terminal_buf, 'buflisted', false)
  vim.api.nvim_buf_set_option(state.terminal_buf, 'modifiable', true)
  
  -- Set a unique buffer name to avoid conflicts
  vim.api.nvim_buf_set_name(state.terminal_buf, '[Floating Command Terminal]')
end

-- Create floating terminal window
local function create_terminal_window()
  local win_config = get_window_config()
  
  state.terminal_win = vim.api.nvim_open_win(state.terminal_buf, true, {
    relative = 'editor',
    width = win_config.width,
    height = win_config.height,
    row = win_config.row,
    col = win_config.col,
    border = config.border,
    title = ' Terminal Command ',
    title_pos = 'center',
  })
  
  -- Set window options
  vim.api.nvim_win_set_option(state.terminal_win, 'winhl', 'Normal:Normal,FloatBorder:FloatBorder')
  vim.api.nvim_win_set_option(state.terminal_win, 'wrap', true)
  vim.api.nvim_win_set_option(state.terminal_win, 'scrolloff', 0)
end


-- Clean up autocmds when closing
local function cleanup_focus_autocmd()
  pcall(vim.api.nvim_del_augroup_by_name, 'FloatingCmdline')
end

-- Close terminal window
local function close_floating_cmdline()
  if state.terminal_win and vim.api.nvim_win_is_valid(state.terminal_win) then
    vim.api.nvim_win_close(state.terminal_win, true)
    state.terminal_win = nil
  end
  
  -- Clean up terminal buffer explicitly to prevent conflicts
  if state.terminal_buf and vim.api.nvim_buf_is_valid(state.terminal_buf) then
    vim.api.nvim_buf_delete(state.terminal_buf, { force = true })
    state.terminal_buf = nil
  end
  
  cleanup_focus_autocmd()
  
  -- Reset all state
  state.is_open = false
  state.original_win = nil
  state.original_buf = nil
end

-- Append output to terminal buffer
local function append_to_terminal(lines)
  if not state.terminal_buf or not vim.api.nvim_buf_is_valid(state.terminal_buf) then
    return
  end
  
  -- Get current buffer content
  local current_lines = vim.api.nvim_buf_get_lines(state.terminal_buf, 0, -1, false)
  
  -- Append new lines
  for _, line in ipairs(lines) do
    table.insert(current_lines, line)
  end
  
  -- Update buffer
  vim.api.nvim_buf_set_lines(state.terminal_buf, 0, -1, false, current_lines)
  
  -- Scroll to bottom
  if state.terminal_win and vim.api.nvim_win_is_valid(state.terminal_win) then
    local line_count = #current_lines
    vim.api.nvim_win_set_cursor(state.terminal_win, {line_count, 0})
  end
end

-- Add new prompt line
local function add_prompt()
  append_to_terminal({config.prompt})
  
  -- Move cursor to end of prompt
  if state.terminal_win and vim.api.nvim_win_is_valid(state.terminal_win) then
    local lines = vim.api.nvim_buf_get_lines(state.terminal_buf, 0, -1, false)
    local last_line = #lines
    vim.api.nvim_win_set_cursor(state.terminal_win, {last_line, #config.prompt})
  end
end

-- Execute command
local function execute_command(cmd)
  if cmd == '' then return end
  
  -- Add to history
  add_to_history(cmd)
  
  -- Commands that should close the floating cmdline immediately
  local immediate_commands = {
    'q', 'quit', 'qa', 'qall', 'wq', 'wqa', 'wqall', 'x', 'exit',
    'cq', 'cquit', 'bd', 'bdelete', 'bw', 'bwipeout'
  }
  
  local should_close_immediately = false
  for _, immediate_cmd in ipairs(immediate_commands) do
    if cmd:match('^' .. immediate_cmd .. '%s*$') or cmd:match('^' .. immediate_cmd .. '!%s*$') then
      should_close_immediately = true
      break
    end
  end
  
  if should_close_immediately then
    close_floating_cmdline()
    vim.cmd('stopinsert')
    
    -- Execute the command
    local ok, err = pcall(function()
      if state.original_win and vim.api.nvim_win_is_valid(state.original_win) then
        vim.api.nvim_set_current_win(state.original_win)
      end
      vim.cmd(cmd)
    end)
    
    if not ok then
      vim.api.nvim_err_writeln('Error: ' .. err)
    end
    return
  end
  
  -- Capture command output with better isolation
  local output = {}
  
  -- Switch to original window first, then set up redirection
  local current_win = vim.api.nvim_get_current_win()
  local target_win = state.original_win
  
  if target_win and vim.api.nvim_win_is_valid(target_win) then
    vim.api.nvim_set_current_win(target_win)
  end
  
  -- Set up output redirection in the target context
  vim.cmd('redir => g:floating_cmdline_output')
  
  -- Commands that might cause buffer conflicts - handle specially
  local buffer_commands = {
    '^e%s', '^edit%s', '^new%s*$', '^vnew%s*$', '^tabnew%s', 
    '^sp%s', '^split%s', '^vs%s', '^vsplit%s', '^tabe%s', '^tabedit%s'
  }
  
  local is_buffer_command = false
  for _, pattern in ipairs(buffer_commands) do
    if cmd:match(pattern) then
      is_buffer_command = true
      break
    end
  end
  
  local ok, result = pcall(function()
    if is_buffer_command then
      -- For buffer/file commands, don't use redir to avoid conflicts
      vim.cmd('redir END')  -- End redir early
      vim.cmd(cmd)
      vim.cmd('redir => g:floating_cmdline_output')  -- Restart for any remaining output
    else
      -- For other commands, use silent to reduce autocmd interference  
      vim.cmd('silent! ' .. cmd)
    end
  end)
  
  vim.cmd('redir END')
  
  -- Switch back to terminal window
  if current_win and vim.api.nvim_win_is_valid(current_win) then
    vim.api.nvim_set_current_win(current_win)
  end
  
  local captured_output = vim.g.floating_cmdline_output or ''
  vim.g.floating_cmdline_output = nil
  
  if not ok then
    table.insert(output, 'Error: ' .. result)
  elseif captured_output and captured_output ~= '' then
    for line in captured_output:gmatch('[^\r\n]+') do
      local trimmed = line:gsub('^%s*(.-)%s*$', '%1')
      if trimmed ~= '' then
        table.insert(output, trimmed)
      end
    end
  end
  
  -- Append output to terminal
  if #output > 0 then
    append_to_terminal(output)
  end
  
  -- Add new prompt for next command
  add_prompt()
end

-- Get current command from terminal buffer
local function get_current_command()
  if not state.terminal_buf or not vim.api.nvim_buf_is_valid(state.terminal_buf) then
    return ''
  end
  
  local lines = vim.api.nvim_buf_get_lines(state.terminal_buf, 0, -1, false)
  local last_line = lines[#lines] or ''
  
  -- Extract command after the prompt
  if last_line:sub(1, #config.prompt) == config.prompt then
    return last_line:sub(#config.prompt + 1)
  end
  
  return ''
end

-- Replace current command line
local function replace_current_command(cmd)
  if not state.terminal_buf or not vim.api.nvim_buf_is_valid(state.terminal_buf) then
    return
  end
  
  local lines = vim.api.nvim_buf_get_lines(state.terminal_buf, 0, -1, false)
  if #lines == 0 then return end
  
  -- Replace the last line with prompt + command
  lines[#lines] = config.prompt .. cmd
  vim.api.nvim_buf_set_lines(state.terminal_buf, 0, -1, false, lines)
  
  -- Move cursor to end
  if state.terminal_win and vim.api.nvim_win_is_valid(state.terminal_win) then
    vim.api.nvim_win_set_cursor(state.terminal_win, {#lines, #lines[#lines]})
  end
end

-- Handle command history
local function navigate_history(direction)
  if #state.command_history == 0 then return end
  
  if direction == 'up' then
    state.history_index = math.min(state.history_index + 1, #state.command_history)
  elseif direction == 'down' then
    state.history_index = math.max(state.history_index - 1, 0)
  end
  
  local cmd = state.history_index > 0 and state.command_history[state.history_index] or ''
  replace_current_command(cmd)
end

-- Set up terminal buffer keymaps
local function setup_terminal_keymaps()
  -- Enter to execute command
  vim.keymap.set('i', '<CR>', function()
    local cmd = get_current_command()
    execute_command(cmd)
  end, { buffer = state.terminal_buf, silent = true })
  
  -- Arrow keys for history navigation
  vim.keymap.set('i', '<Up>', function()
    navigate_history('up')
  end, { buffer = state.terminal_buf, silent = true })
  
  vim.keymap.set('i', '<Down>', function()
    navigate_history('down')
  end, { buffer = state.terminal_buf, silent = true })
end

-- Setup mode-aware close handling
local function setup_mode_autocmds()
  -- Create autocmd group
  local group = vim.api.nvim_create_augroup('FloatingCmdline', { clear = true })
  
  -- Handle Esc, Ctrl+C, Ctrl+[ in normal mode to close
  vim.api.nvim_create_autocmd('ModeChanged', {
    group = group,
    buffer = state.terminal_buf,
    callback = function()
      if not state.is_open then return end
      
      local mode = vim.api.nvim_get_mode().mode
      if mode == 'n' then
        -- In normal mode, set up keymaps to close on escape keys
        vim.keymap.set('n', '<Esc>', function()
          close_floating_cmdline()
        end, { buffer = state.terminal_buf, silent = true, nowait = true })
        
        vim.keymap.set('n', '<C-c>', function()
          close_floating_cmdline()
        end, { buffer = state.terminal_buf, silent = true, nowait = true })
        
        vim.keymap.set('n', '<C-[>', function()
          close_floating_cmdline()
        end, { buffer = state.terminal_buf, silent = true, nowait = true })
        
        -- Also handle Ctrl+W for window navigation (should close)
        vim.keymap.set('n', '<C-w>', function()
          close_floating_cmdline()
        end, { buffer = state.terminal_buf, silent = true, nowait = true })
      else
        -- In insert mode, remove the normal mode keymaps to allow natural behavior
        pcall(vim.keymap.del, 'n', '<Esc>', { buffer = state.terminal_buf })
        pcall(vim.keymap.del, 'n', '<C-c>', { buffer = state.terminal_buf })
        pcall(vim.keymap.del, 'n', '<C-[>', { buffer = state.terminal_buf })
        pcall(vim.keymap.del, 'n', '<C-w>', { buffer = state.terminal_buf })
      end
    end,
  })
end

-- Setup autocmd to close when focus leaves our window
local function setup_focus_autocmd()
  -- Get or create autocmd group
  local group = vim.api.nvim_create_augroup('FloatingCmdline', { clear = false })
  
  -- Monitor window enter events with a delay to avoid closing during command execution
  vim.api.nvim_create_autocmd('WinEnter', {
    group = group,
    callback = function()
      if not state.is_open then return end
      
      -- Delay the check slightly to allow command execution context switches
      vim.defer_fn(function()
        if not state.is_open then return end
        
        local current_win = vim.api.nvim_get_current_win()
        
        -- Check if current window is our terminal window
        local is_our_window = state.terminal_win and vim.api.nvim_win_is_valid(state.terminal_win) and current_win == state.terminal_win
        
        -- If focus moved to a window that's not ours, close the floating cmdline
        if not is_our_window then
          close_floating_cmdline()
          vim.cmd('stopinsert')
        end
      end, 50) -- 50ms delay
    end,
  })
end

-- Open floating command line
function M.open()
  if state.is_open then return end
  
  -- Store original window and buffer context
  state.original_win = vim.api.nvim_get_current_win()
  state.original_buf = vim.api.nvim_get_current_buf()
  
  -- Create terminal buffer and window
  create_terminal_buffer()
  create_terminal_window()
  setup_terminal_keymaps()
  setup_mode_autocmds()
  setup_focus_autocmd()
  
  -- Reset state
  state.history_index = 0
  state.is_open = true
  
  -- Initialize terminal with first prompt
  add_prompt()
  
  -- Start in insert mode
  vim.cmd('startinsert!')
end

-- Setup function
function M.setup(opts)
  opts = opts or {}
  
  -- Override config
  for k, v in pairs(opts) do
    config[k] = v
  end
  
  -- Load history
  load_history()
  
  -- Set up global keymap
  vim.keymap.set('n', '<C-o>', M.open, { silent = true, desc = 'Open floating command line' })
end

return M