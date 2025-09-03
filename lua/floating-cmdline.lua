local M = {}

-- Configuration
local config = {
  width_ratio = 0.8,  -- Width relative to screen
  height_ratio = 0.6, -- Height relative to screen for output window
  border = 'rounded', -- Border style
}

-- State
local state = {
  -- Single window (terminal-style)
  buf = nil,
  win = nil,
  
  is_open = false,
  
  -- Store original context
  original_win = nil,
  original_buf = nil,
}

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
local function create_buffer()
  state.buf = vim.api.nvim_create_buf(false, true)
  
  vim.api.nvim_buf_set_option(state.buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(state.buf, 'filetype', 'vim')  -- For command completion
  vim.api.nvim_buf_set_option(state.buf, 'bufhidden', 'hide')  -- Keep buffer when window closes
  vim.api.nvim_buf_set_option(state.buf, 'swapfile', false)
  vim.api.nvim_buf_set_option(state.buf, 'buflisted', false)
  vim.api.nvim_buf_set_option(state.buf, 'modifiable', false)  -- Start as readonly
  
  -- Set up custom command completion
  vim.api.nvim_buf_set_option(state.buf, 'completefunc', 'v:lua.floating_cmdline_complete')
  
  -- Disable Copilot for this buffer
  vim.api.nvim_buf_set_var(state.buf, 'copilot_enabled', false)
  
  vim.api.nvim_buf_set_name(state.buf, '[Floating Terminal]')
end

-- Create floating window
local function create_window()
  local win_config = get_window_config()
  
  -- Create single floating window
  state.win = vim.api.nvim_open_win(state.buf, true, {
    relative = 'editor',
    width = win_config.width,
    height = win_config.height,
    row = win_config.row,
    col = win_config.col,
    border = config.border,
    title = ' Terminal ',
    title_pos = 'center',
  })
  
  -- Window options
  vim.api.nvim_win_set_option(state.win, 'wrap', true)
  vim.api.nvim_win_set_option(state.win, 'scrolloff', 0)
end

-- Append content to buffer
local function append_to_buffer(lines)
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end
  
  -- Get current content
  local current_lines = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
  
  -- If buffer only contains one empty line, replace it instead of appending
  if #current_lines == 1 and current_lines[1] == '' then
    current_lines = {}
  end
  
  -- Append new lines
  for _, line in ipairs(lines) do
    table.insert(current_lines, line)
  end
  
  -- Update buffer
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, current_lines)
  
  -- Scroll to bottom if window is valid
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    local line_count = #current_lines
    vim.api.nvim_win_set_cursor(state.win, {line_count, 0})
  end
end



-- Custom completion function for command completion
local function command_complete(findstart, base)
  if findstart == 1 then
    local line = vim.fn.getline('.')
    local col = vim.fn.col('.') - 1
    
    -- Check if we're completing a command or arguments
    local has_space = line:find('%s')
    
    if not has_space then
      -- Completing command name - start from beginning of line
      return 0
    else
      -- Completing arguments - find the start of current word
      -- Look backwards for word boundaries (space, =, comma, etc.)
      local word_start = col
      for i = col, 0, -1 do
        local char = line:sub(i, i)
        -- Break on common word separators
        if char:match('[%s=,:]') then
          word_start = i
          break
        end
        word_start = i - 1
      end
      
      return word_start
    end
  else
    -- Get the full command line
    local line = vim.fn.getline('.')
    
    -- Check if we're completing command or arguments
    local has_space = line:find('%s')
    
    if not has_space then
      -- Completing command name - use base which has the partial text
      local completions = vim.fn.getcompletion(base or '', 'cmdline')
      return completions
    else
      -- Completing arguments - need full context
      local col = vim.fn.col('.') - 1
      
      -- Find where the current word starts (for arguments after =, :, etc.)
      local word_start = col
      for i = col, 0, -1 do
        local char = line:sub(i, i)
        if char:match('[%s=,:]') then
          word_start = i
          break
        end
        word_start = i - 1
      end
      
      -- Get the prefix (everything before the word being completed)
      local prefix = ''
      if word_start > 0 then
        prefix = line:sub(1, word_start)
      end
      
      -- Build the full context for completion
      local context = prefix .. (base or '')
      
      -- Get completions from Vim
      local completions = vim.fn.getcompletion(context, 'cmdline')
      
      return completions
    end
  end
end



-- Execute current line as command (terminal-style)
local function execute_current_line()
  -- Get cursor position and current line
  local cursor = vim.api.nvim_win_get_cursor(state.win)
  local line_num = cursor[1]
  local current_line = vim.api.nvim_buf_get_lines(state.buf, line_num - 1, line_num, false)[1]
  
  -- Trim whitespace to get command
  local cmd = current_line:gsub('^%s*(.-)%s*$', '%1')
  if cmd == '' then
    return  -- Empty line, nothing to execute
  end
  
  -- Close any open completion popup
  if vim.fn.pumvisible() == 1 then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-e>', true, false, true), 'n', false)
  end
  
  -- Add to Vim's native command history
  vim.fn.histadd('cmd', cmd)
  
  -- Store original context
  local target_win = state.original_win
  if target_win and vim.api.nvim_win_is_valid(target_win) then
    vim.api.nvim_set_current_win(target_win)
  end
  
  -- Execute command and capture output
  local ok, result = pcall(vim.fn.execute, cmd)
  
  -- Switch back to our window
  vim.api.nvim_set_current_win(state.win)
  
  -- Temporarily make buffer modifiable for output
  vim.api.nvim_buf_set_option(state.buf, 'modifiable', true)
  
  -- Process output and add to buffer
  if not ok then
    append_to_buffer({'Error: ' .. result})
  elseif result and result ~= '' then
    -- Skip output for Explore command (produces noise)
    local is_explore = cmd:match('^[Ee]xplore?%s*')
    if not is_explore then
      local output_lines = {}
      for line in result:gmatch('[^\r\n]+') do
        local trimmed = line:gsub('^%s*(.-)%s*$', '%1')
        if trimmed ~= '' then
          table.insert(output_lines, '  ' .. trimmed)
        end
      end
      if #output_lines > 0 then
        append_to_buffer(output_lines)
      end
    end
  end
  
  -- Add new empty line for next command and move cursor there
  append_to_buffer({''})
  local total_lines = vim.api.nvim_buf_line_count(state.buf)
  vim.api.nvim_win_set_cursor(state.win, {total_lines, 0})
  
  -- Enter insert mode at end of line
  vim.cmd('startinsert!')
end

-- Enter insert mode terminal-style (add new line at bottom)
local function enter_insert_mode()
  -- Make buffer modifiable for editing
  vim.api.nvim_buf_set_option(state.buf, 'modifiable', true)
  
  -- Check if last line is already empty
  local total_lines = vim.api.nvim_buf_line_count(state.buf)
  local last_line = vim.api.nvim_buf_get_lines(state.buf, total_lines - 1, total_lines, false)[1] or ''
  
  -- Only add empty line if the last line is not empty
  if last_line:match('%S') then  -- Contains non-whitespace characters
    append_to_buffer({''})
    total_lines = vim.api.nvim_buf_line_count(state.buf)
  end
  
  -- Move cursor to the last line and enter insert mode
  vim.api.nvim_win_set_cursor(state.win, {total_lines, 0})
  vim.cmd('startinsert!')
end

-- Get command at cursor line (for rerun functionality)
local function get_command_at_cursor()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return nil
  end
  
  local cursor = vim.api.nvim_win_get_cursor(state.win)
  local line_num = cursor[1]
  local current_line = vim.api.nvim_buf_get_lines(state.buf, line_num - 1, line_num, false)[1]
  
  -- Check if this line looks like a command (not indented output)
  if current_line and not current_line:match('^%s%s') and current_line:match('%S') then
    local cmd = current_line:gsub('^%s*(.-)%s*$', '%1')
    return cmd, line_num
  end
  
  return nil
end

-- Find the output range for a command at given line
local function get_command_output_range(cmd_line)
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return nil, nil
  end
  
  local lines = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
  local total_lines = #lines
  
  -- Output starts right after the command line
  local start_line = cmd_line + 1
  if start_line > total_lines then
    return nil, nil  -- No output for this command
  end
  
  -- Find where output ends (next command or end of buffer)
  local end_line = total_lines
  for i = start_line, total_lines do
    local line = lines[i]
    if line and not line:match('^%s%s') and line:match('%S') then
      -- Found next command (not indented), output ends before it
      end_line = i - 1
      break
    end
  end
  
  if end_line < start_line then
    return nil, nil  -- No actual output
  end
  
  return start_line, end_line
end

-- Rerun command at cursor and replace its output
local function rerun_command_at_cursor()
  local cmd, cmd_line = get_command_at_cursor()
  if not cmd then
    return  -- Not on a command line
  end
  
  -- Temporarily make buffer modifiable for rerun
  vim.api.nvim_buf_set_option(state.buf, 'modifiable', true)
  
  -- Delete old output (but keep the command line)
  local start_line, end_line = get_command_output_range(cmd_line)
  if start_line then
    vim.api.nvim_buf_set_lines(state.buf, start_line - 1, end_line, false, {})
  end
  
  -- Store original context
  local target_win = state.original_win
  if target_win and vim.api.nvim_win_is_valid(target_win) then
    vim.api.nvim_set_current_win(target_win)
  end
  
  -- Execute command and capture output
  local ok, result = pcall(vim.fn.execute, cmd)
  
  -- Switch back to our window
  vim.api.nvim_set_current_win(state.win)
  
  -- Insert new output after the command line
  local output_lines = {}
  if not ok then
    table.insert(output_lines, 'Error: ' .. result)
  elseif result and result ~= '' then
    -- Skip output for Explore command (produces noise)
    local is_explore = cmd:match('^[Ee]xplore?%s*')
    if not is_explore then
      for line in result:gmatch('[^\r\n]+') do
        local trimmed = line:gsub('^%s*(.-)%s*$', '%1')
        if trimmed ~= '' then
          table.insert(output_lines, '  ' .. trimmed)
        end
      end
    end
  end
  
  -- Insert output after the command line
  if #output_lines > 0 then
    vim.api.nvim_buf_set_lines(state.buf, cmd_line, cmd_line, false, output_lines)
  end
  
  -- Position cursor back on the command line
  vim.api.nvim_win_set_cursor(state.win, {cmd_line, 0})
  
  -- Make buffer readonly again
  vim.api.nvim_buf_set_option(state.buf, 'modifiable', false)
end

-- Delete command at cursor and its output
local function delete_command_at_cursor()
  local cmd, cmd_line = get_command_at_cursor()
  if not cmd then
    return  -- Not on a command line, do nothing
  end
  
  -- Temporarily make buffer modifiable for deletion
  vim.api.nvim_buf_set_option(state.buf, 'modifiable', true)
  
  -- Find the output range for this command
  local start_line, end_line = get_command_output_range(cmd_line)
  
  -- Determine what to delete
  local delete_start = cmd_line
  local delete_end = end_line or cmd_line
  
  -- Delete the command line and its output
  vim.api.nvim_buf_set_lines(state.buf, delete_start - 1, delete_end, false, {})
  
  -- Make buffer readonly again
  vim.api.nvim_buf_set_option(state.buf, 'modifiable', false)
  
  -- Adjust cursor position
  local new_line_count = vim.api.nvim_buf_line_count(state.buf)
  local new_cursor_line = math.min(delete_start, new_line_count)
  if new_cursor_line < 1 then
    new_cursor_line = 1
  end
  vim.api.nvim_win_set_cursor(state.win, {new_cursor_line, 0})
end

-- Jump to next command line
local function jump_to_next_command()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end
  
  local cursor = vim.api.nvim_win_get_cursor(state.win)
  local current_line = cursor[1]
  local lines = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
  
  -- Search forward from next line for a command (not indented output)
  for i = current_line + 1, #lines do
    local line = lines[i]
    if line and not line:match('^%s%s') and line:match('%S') then
      vim.api.nvim_win_set_cursor(state.win, {i, 0})
      return
    end
  end
end

-- Jump to previous command line
local function jump_to_previous_command()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end
  
  local cursor = vim.api.nvim_win_get_cursor(state.win)
  local current_line = cursor[1]
  local lines = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
  
  -- Search backward from previous line for a command (not indented output)
  for i = current_line - 1, 1, -1 do
    local line = lines[i]
    if line and not line:match('^%s%s') and line:match('%S') then
      vim.api.nvim_win_set_cursor(state.win, {i, 0})
      return
    end
  end
end

-- Setup keymaps for terminal-style buffer
local function setup_keymaps()
  -- Set up autocmds for modifiable/readonly behavior
  local augroup = vim.api.nvim_create_augroup('FloatingTerminal', { clear = true })
  
  -- Make buffer readonly when leaving insert mode
  vim.api.nvim_create_autocmd('InsertLeave', {
    group = augroup,
    buffer = state.buf,
    callback = function()
      vim.api.nvim_buf_set_option(state.buf, 'modifiable', false)
    end,
  })
  
  -- Insert mode: Enter to execute current line
  vim.keymap.set('i', '<CR>', function()
    -- Accept completion if popup is open
    if vim.fn.pumvisible() == 1 then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-y>', true, false, true), 'n', false)
      -- Wait for completion to be inserted, then execute
      vim.defer_fn(function()
        execute_current_line()
      end, 10)
    else
      -- No popup, execute immediately
      execute_current_line()
    end
  end, { buffer = state.buf, silent = true })
  
  -- Insert mode: Ctrl-N for context-aware completion
  vim.keymap.set('i', '<C-n>', function()
    if vim.fn.pumvisible() == 1 then
      -- Popup is open, navigate down
      return '<C-n>'
    else
      -- No popup, trigger user completion
      return '<C-x><C-u>'
    end
  end, { buffer = state.buf, silent = true, expr = true })
  
  -- Normal mode: Insert mode triggers (terminal-style)
  vim.keymap.set('n', 'i', enter_insert_mode, { buffer = state.buf, silent = true, desc = 'Enter insert mode (add new line)' })
  vim.keymap.set('n', 'a', enter_insert_mode, { buffer = state.buf, silent = true, desc = 'Enter insert mode (add new line)' })
  vim.keymap.set('n', 'o', enter_insert_mode, { buffer = state.buf, silent = true, desc = 'Enter insert mode (add new line)' })
  vim.keymap.set('n', 'O', enter_insert_mode, { buffer = state.buf, silent = true, desc = 'Enter insert mode (add new line)' })
  vim.keymap.set('n', 'A', enter_insert_mode, { buffer = state.buf, silent = true, desc = 'Enter insert mode (add new line)' })
  vim.keymap.set('n', 'I', enter_insert_mode, { buffer = state.buf, silent = true, desc = 'Enter insert mode (add new line)' })
  
  -- Normal mode: Enter to rerun command at cursor
  vim.keymap.set('n', '<CR>', function()
    rerun_command_at_cursor()
  end, { buffer = state.buf, silent = true, desc = 'Rerun command at cursor' })
  
  -- Normal mode: dd to delete command and its output
  vim.keymap.set('n', 'dd', function()
    delete_command_at_cursor()
  end, { buffer = state.buf, silent = true, desc = 'Delete command and its output' })
  
  -- Normal mode: Command navigation
  vim.keymap.set('n', ']c', function()
    jump_to_next_command()
  end, { buffer = state.buf, silent = true, desc = 'Jump to next command' })
  
  vim.keymap.set('n', '[c', function()
    jump_to_previous_command()
  end, { buffer = state.buf, silent = true, desc = 'Jump to previous command' })
  
  -- Normal mode: Close window
  vim.keymap.set('n', '<C-c>', function()
    M.close()
  end, { buffer = state.buf, silent = true })
  
  vim.keymap.set('n', 'q', function()
    M.close()
  end, { buffer = state.buf, silent = true })
end

-- Close floating terminal
function M.close()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
    state.win = nil
  end
  
  -- Keep buffer alive, don't delete it
  -- This preserves history between open/close cycles
  
  state.is_open = false
  state.original_win = nil
  state.original_buf = nil
end

-- Open floating terminal
function M.open()
  if state.is_open then return end
  
  -- Store original context
  state.original_win = vim.api.nvim_get_current_win()
  state.original_buf = vim.api.nvim_get_current_buf()
  
  -- Create buffer only if it doesn't exist or is invalid
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    create_buffer()
  end
  
  -- Create window
  create_window()
  
  -- Setup keymaps (needed each time since they're buffer-local)
  setup_keymaps()
  
  state.is_open = true
  
  -- Start in insert mode (terminal-style)
  enter_insert_mode()
end

-- Expose completion function for v:lua access
M.command_complete = command_complete
_G.floating_cmdline_complete = command_complete

-- Setup function
function M.setup(opts)
  opts = opts or {}
  
  -- Override config
  for k, v in pairs(opts) do
    config[k] = v
  end
  
  -- Set up global keymap
  vim.keymap.set('n', '<C-o>', M.open, { silent = true, desc = 'Open floating command line' })
end

return M