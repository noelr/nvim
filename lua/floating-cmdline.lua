local M = {}

-- Configuration
local config = {
  width_ratio = 0.8,  -- Width relative to screen
  height_ratio = 0.6, -- Height relative to screen for output window
  border = 'rounded', -- Border style
}

-- State
local state = {
  -- Prompt window
  prompt_buf = nil,
  prompt_win = nil,
  
  -- Output window
  output_buf = nil,
  output_win = nil,
  
  is_open = false,
  last_focused_window = 'prompt',  -- Remember which window had focus ('prompt' or 'output')
  
  -- Store original context
  original_win = nil,
  original_buf = nil,
}

-- Get window dimensions and positions for both windows
local function get_window_configs()
  local screen_width = vim.o.columns
  local screen_height = vim.o.lines
  
  local width = math.floor(screen_width * config.width_ratio)
  local output_height = math.floor(screen_height * config.height_ratio)
  local prompt_height = 1  -- Single line for prompt
  
  local col = math.floor((screen_width - width) / 2)
  local output_row = math.floor((screen_height - output_height - prompt_height - 1) / 2)
  local prompt_row = output_row + output_height + 1
  
  return {
    prompt = {
      width = width,
      height = prompt_height,
      col = col,
      row = prompt_row,
    },
    output = {
      width = width,
      height = output_height,
      col = col,
      row = output_row,
    }
  }
end

-- Create output buffer
local function create_output_buffer()
  state.output_buf = vim.api.nvim_create_buf(false, true)
  
  vim.api.nvim_buf_set_option(state.output_buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(state.output_buf, 'bufhidden', 'hide')  -- Keep buffer when window closes
  vim.api.nvim_buf_set_option(state.output_buf, 'swapfile', false)
  vim.api.nvim_buf_set_option(state.output_buf, 'buflisted', false)
  vim.api.nvim_buf_set_option(state.output_buf, 'modifiable', false)  -- Read-only
  
  vim.api.nvim_buf_set_name(state.output_buf, '[Command Output]')
end

-- Create prompt buffer
local function create_prompt_buffer()
  state.prompt_buf = vim.api.nvim_create_buf(false, true)
  
  vim.api.nvim_buf_set_option(state.prompt_buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(state.prompt_buf, 'filetype', 'vim')  -- For command completion
  vim.api.nvim_buf_set_option(state.prompt_buf, 'bufhidden', 'hide')  -- Keep buffer when window closes
  vim.api.nvim_buf_set_option(state.prompt_buf, 'swapfile', false)
  vim.api.nvim_buf_set_option(state.prompt_buf, 'buflisted', false)
  vim.api.nvim_buf_set_option(state.prompt_buf, 'modifiable', true)
  
  -- Set up custom command completion
  vim.api.nvim_buf_set_option(state.prompt_buf, 'completefunc', 'v:lua.floating_cmdline_complete')
  
  -- Disable Copilot for this buffer
  vim.api.nvim_buf_set_var(state.prompt_buf, 'copilot_enabled', false)
  
  vim.api.nvim_buf_set_name(state.prompt_buf, '[Command Prompt]')
end

-- Create floating windows
local function create_windows()
  local configs = get_window_configs()
  
  -- Determine which window should get initial focus
  local focus_output = (state.last_focused_window == 'output')
  local focus_prompt = not focus_output
  
  -- Create output window first (appears above prompt)
  state.output_win = vim.api.nvim_open_win(state.output_buf, focus_output, {
    relative = 'editor',
    width = configs.output.width,
    height = configs.output.height,
    row = configs.output.row,
    col = configs.output.col,
    border = config.border,
    title = ' Output ',
    title_pos = 'center',
  })
  
  -- Output window options
  vim.api.nvim_win_set_option(state.output_win, 'wrap', true)
  vim.api.nvim_win_set_option(state.output_win, 'scrolloff', 0)
  
  -- Create prompt window (appears below output)
  state.prompt_win = vim.api.nvim_open_win(state.prompt_buf, focus_prompt, {
    relative = 'editor',
    width = configs.prompt.width,
    height = configs.prompt.height,
    row = configs.prompt.row,
    col = configs.prompt.col,
    border = config.border,
    title = ' Command ',
    title_pos = 'center',
  })
  
  -- Prompt window options
  vim.api.nvim_win_set_option(state.prompt_win, 'wrap', false)
  vim.api.nvim_win_set_option(state.prompt_win, 'scrolloff', 0)
end

-- Append output to output buffer
local function append_to_output(lines)
  if not state.output_buf or not vim.api.nvim_buf_is_valid(state.output_buf) then
    return
  end
  
  -- Make buffer temporarily modifiable
  vim.api.nvim_buf_set_option(state.output_buf, 'modifiable', true)
  
  -- Get current content
  local current_lines = vim.api.nvim_buf_get_lines(state.output_buf, 0, -1, false)
  
  -- Append new lines
  for _, line in ipairs(lines) do
    table.insert(current_lines, line)
  end
  
  -- Update buffer
  vim.api.nvim_buf_set_lines(state.output_buf, 0, -1, false, current_lines)
  
  -- Make buffer read-only again
  vim.api.nvim_buf_set_option(state.output_buf, 'modifiable', false)
  
  -- Scroll to bottom if window is valid
  if state.output_win and vim.api.nvim_win_is_valid(state.output_win) then
    local line_count = #current_lines
    vim.api.nvim_win_set_cursor(state.output_win, {line_count, 0})
  end
end

-- Clear prompt buffer
local function clear_prompt()
  if state.prompt_buf and vim.api.nvim_buf_is_valid(state.prompt_buf) then
    vim.api.nvim_buf_set_lines(state.prompt_buf, 0, -1, false, {''})
    if state.prompt_win and vim.api.nvim_win_is_valid(state.prompt_win) then
      vim.api.nvim_win_set_cursor(state.prompt_win, {1, 0})
    end
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



-- Execute command
local function execute_command(cmd)
  
  -- Close any open completion popup
  if vim.fn.pumvisible() == 1 then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-e>', true, false, true), 'n', false)
  end
  
  -- Add to Vim's native command history
  vim.fn.histadd('cmd', cmd)
  
  -- Show command in output
  append_to_output({'> ' .. cmd})
  
  -- Store original context
  local current_win = vim.api.nvim_get_current_win()
  local target_win = state.original_win
  
  if target_win and vim.api.nvim_win_is_valid(target_win) then
    vim.api.nvim_set_current_win(target_win)
  end
  
  -- Execute command and capture output
  local ok, result = pcall(vim.fn.execute, cmd)
  
  -- Count immediate output lines
  local immediate_output_count = 0
  
  -- Process immediate output
  if not ok then
    append_to_output({'Error: ' .. result})
    immediate_output_count = 1
  elseif result and result ~= '' then
    -- Skip output for Explore command (produces noise)
    local is_explore = cmd:match('^[Ee]xplore?%s*')
    if not is_explore then
      for line in result:gmatch('[^\r\n]+') do
        local trimmed = line:gsub('^%s*(.-)%s*$', '%1')
        if trimmed ~= '' then
          append_to_output({'  ' .. trimmed})
          immediate_output_count = immediate_output_count + 1
        end
      end
    end
  end
  
  -- Switch back to prompt window
  if state.prompt_win and vim.api.nvim_win_is_valid(state.prompt_win) then
    vim.api.nvim_set_current_win(state.prompt_win)
    clear_prompt()
  end
end

-- Get current command from prompt
local function get_current_command()
  if not state.prompt_buf or not vim.api.nvim_buf_is_valid(state.prompt_buf) then
    return ''
  end
  
  local lines = vim.api.nvim_buf_get_lines(state.prompt_buf, 0, -1, false)
  local cmd = lines[1] or ''
  -- Trim whitespace
  return cmd:gsub('^%s*(.-)%s*$', '%1')
end

-- Find command at or above cursor in output buffer
local function get_command_at_cursor()
  if not state.output_buf or not vim.api.nvim_buf_is_valid(state.output_buf) then
    return nil, nil
  end
  
  -- Get cursor position
  local cursor = vim.api.nvim_win_get_cursor(state.output_win)
  local current_line = cursor[1]
  
  -- Get all lines in buffer
  local lines = vim.api.nvim_buf_get_lines(state.output_buf, 0, -1, false)
  
  -- Search backwards from cursor to find command
  for i = current_line, 1, -1 do
    local line = lines[i]
    if line and line:match('^> ') then
      -- Found command, extract it without the '> ' prefix
      local cmd = line:sub(3)
      return cmd, i
    end
  end
  
  return nil, nil
end

-- Find the range of lines containing a command's output
local function get_command_output_range(cmd_line)
  if not state.output_buf or not vim.api.nvim_buf_is_valid(state.output_buf) then
    return nil, nil
  end
  
  local lines = vim.api.nvim_buf_get_lines(state.output_buf, 0, -1, false)
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
    if line and line:match('^> ') then
      -- Found next command, output ends before it
      end_line = i - 1
      break
    end
  end
  
  if end_line < start_line then
    return nil, nil  -- No actual output
  end
  
  return start_line, end_line
end

-- Delete command output (optionally including the command line itself)
local function delete_command_output(cmd_line, include_command)
  local start_line, end_line = get_command_output_range(cmd_line)
  
  -- Determine what to delete
  local delete_start = include_command and cmd_line or (start_line or cmd_line + 1)
  local delete_end = end_line or cmd_line
  
  -- Skip if nothing to delete
  if not include_command and not start_line then
    return nil, nil -- No output to delete
  end
  
  -- Make buffer modifiable
  vim.api.nvim_buf_set_option(state.output_buf, 'modifiable', true)
  
  -- Delete the lines
  if delete_start <= delete_end then
    vim.api.nvim_buf_set_lines(state.output_buf, delete_start - 1, delete_end, false, {})
  end
  
  -- Make buffer read-only again
  vim.api.nvim_buf_set_option(state.output_buf, 'modifiable', false)
  
  return delete_start, delete_end
end

-- Delete command and its output at cursor
local function delete_command_at_cursor()
  local cmd, cmd_line = get_command_at_cursor()
  if not cmd then
    vim.api.nvim_echo({{'No command found at cursor', 'WarningMsg'}}, false, {})
    return
  end
  
  -- Delete command and its output
  local delete_start, delete_end = delete_command_output(cmd_line, true)
  if not delete_start then
    return
  end
  
  -- Adjust cursor position if needed
  local new_line_count = vim.api.nvim_buf_line_count(state.output_buf)
  if delete_start - 1 <= new_line_count and delete_start > 1 then
    vim.api.nvim_win_set_cursor(state.output_win, {delete_start - 1, 0})
  elseif new_line_count > 0 then
    vim.api.nvim_win_set_cursor(state.output_win, {math.min(delete_start, new_line_count), 0})
  end
end

-- Rerun the command at cursor and replace its output
local function rerun_command_at_cursor()
  local cmd, cmd_line = get_command_at_cursor()
  if not cmd then
    vim.api.nvim_echo({{'No command found at cursor', 'WarningMsg'}}, false, {})
    return
  end
  
  -- Delete old output (but keep the command line)
  delete_command_output(cmd_line, false)
  
  -- Set cursor to the command line to insert output after it
  vim.api.nvim_win_set_cursor(state.output_win, {cmd_line, 0})
  
  -- Helper function to insert at specific location
  local insert_line = cmd_line + 1
  local function insert_at_location(new_lines)
    if not state.output_buf or not vim.api.nvim_buf_is_valid(state.output_buf) then
      return
    end
    
    -- Make buffer temporarily modifiable
    vim.api.nvim_buf_set_option(state.output_buf, 'modifiable', true)
    
    -- Insert new lines at the specific position
    for i, line in ipairs(new_lines) do
      vim.api.nvim_buf_set_lines(state.output_buf, insert_line - 1, insert_line - 1, false, {line})
      insert_line = insert_line + 1
    end
    
    -- Make buffer read-only again
    vim.api.nvim_buf_set_option(state.output_buf, 'modifiable', false)
    
    -- Move cursor to show the new output
    if state.output_win and vim.api.nvim_win_is_valid(state.output_win) then
      vim.api.nvim_win_set_cursor(state.output_win, {cmd_line, 0})
    end
  end
  
  -- Store original context
  local current_win = vim.api.nvim_get_current_win()
  local target_win = state.original_win
  
  if target_win and vim.api.nvim_win_is_valid(target_win) then
    vim.api.nvim_set_current_win(target_win)
  end
  
  -- Execute command and capture output
  local ok, result = pcall(vim.fn.execute, cmd)
  
  -- Process immediate output
  if not ok then
    insert_at_location({'Error: ' .. result})
  elseif result and result ~= '' then
    -- Skip output for Explore command
    local is_explore = cmd:match('^[Ee]xplore?%s*')
    if not is_explore then
      for line in result:gmatch('[^\r\n]+') do
        local trimmed = line:gsub('^%s*(.-)%s*$', '%1')
        if trimmed ~= '' then
          insert_at_location({'  ' .. trimmed})
        end
      end
    end
  end
  
  -- Switch back to output window
  vim.api.nvim_set_current_win(current_win)
  
  -- Make buffer read-only again
  vim.api.nvim_buf_set_option(state.output_buf, 'modifiable', false)
end

-- Replace current command in prompt
local function replace_current_command(cmd)
  if not state.prompt_buf or not vim.api.nvim_buf_is_valid(state.prompt_buf) then
    return
  end
  
  vim.api.nvim_buf_set_lines(state.prompt_buf, 0, -1, false, {cmd})
  
  -- Move cursor to end
  if state.prompt_win and vim.api.nvim_win_is_valid(state.prompt_win) then
    vim.api.nvim_win_set_cursor(state.prompt_win, {1, #cmd})
  end
end

-- Jump to next command line (line starting with '> ')
local function jump_to_next_command()
  if not state.output_win or not vim.api.nvim_win_is_valid(state.output_win) then
    return
  end
  
  local cursor = vim.api.nvim_win_get_cursor(state.output_win)
  local current_line = cursor[1]
  local lines = vim.api.nvim_buf_get_lines(state.output_buf, 0, -1, false)
  
  -- Search forward from next line
  for i = current_line + 1, #lines do
    if lines[i] and lines[i]:match('^> ') then
      vim.api.nvim_win_set_cursor(state.output_win, {i, 0})
      return
    end
  end
end

-- Jump to previous command line (line starting with '> ')
local function jump_to_previous_command()
  if not state.output_win or not vim.api.nvim_win_is_valid(state.output_win) then
    return
  end
  
  local cursor = vim.api.nvim_win_get_cursor(state.output_win)
  local current_line = cursor[1]
  local lines = vim.api.nvim_buf_get_lines(state.output_buf, 0, -1, false)
  
  -- Search backward from previous line
  for i = current_line - 1, 1, -1 do
    if lines[i] and lines[i]:match('^> ') then
      vim.api.nvim_win_set_cursor(state.output_win, {i, 0})
      return
    end
  end
end

-- Toggle between prompt and output windows
local function toggle_between_windows()
  local current_win = vim.api.nvim_get_current_win()
  
  if current_win == state.prompt_win then
    -- Switch to output window - always ensure normal mode
    if state.output_win and vim.api.nvim_win_is_valid(state.output_win) then
      vim.api.nvim_set_current_win(state.output_win)
      vim.cmd('stopinsert')  -- Force normal mode in output window
    end
  elseif current_win == state.output_win then
    -- Switch to prompt window - always enter insert mode
    if state.prompt_win and vim.api.nvim_win_is_valid(state.prompt_win) then
      vim.api.nvim_set_current_win(state.prompt_win)
      vim.cmd('startinsert!')  -- Always enter insert mode in prompt
    end
  end
end

-- Handle window navigation commands (C-w prefix)
local function handle_window_command()
  -- Get the next character after C-w
  local char = vim.fn.getchar()
  local key = type(char) == 'number' and vim.fn.nr2char(char) or char
  
  local current_win = vim.api.nvim_get_current_win()
  
  -- Handle different window commands
  if key == 'w' or key == '\23' then  -- C-w w or C-w C-w (\23 is Ctrl-W)
    toggle_between_windows()
  elseif key == 'W' then  -- C-w W (cycle backwards)
    toggle_between_windows()
  elseif key == 'h' or key == 'j' or key == 'k' or key == 'l' then
    -- Directional navigation - simplified to toggle since we only have 2 windows
    -- In a vertical split: h/l toggles, j/k does nothing
    -- In a horizontal split: j/k toggles, h/l does nothing
    -- For simplicity, all directions toggle between the two windows
    toggle_between_windows()
  elseif key == 'c' or key == 'q' then  -- C-w c or C-w q (close window)
    M.close()
  elseif key == 'o' or key == '\15' then  -- C-w o or C-w C-o (only/maximize)
    -- Could implement maximize behavior, for now just ignore
    -- Alternatively, could close the floating cmdline
  elseif key == 'p' or key == '\16' then  -- C-w p or C-w C-p (previous window)
    toggle_between_windows()
  elseif key == '\27' then  -- Escape
    -- User pressed Escape after C-w, cancel the command
    return
  else
    -- Unknown command, could show a message or just ignore
    -- For now, just ignore
  end
end

-- Setup keymaps for prompt buffer
local function setup_prompt_keymaps()
  -- Enter to execute command
  vim.keymap.set('i', '<CR>', function()
    -- Accept completion if popup is open
    if vim.fn.pumvisible() == 1 then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-y>', true, false, true), 'n', false)
      -- Wait for completion to be inserted, then execute
      vim.defer_fn(function()
        local cmd = get_current_command()
        if cmd ~= '' then
          execute_command(cmd)
        end
      end, 10)
    else
      -- No popup, execute immediately
      local cmd = get_current_command()
      if cmd ~= '' then
        execute_command(cmd)
      end
    end
  end, { buffer = state.prompt_buf, silent = true })
  
  -- Ctrl-N for completion
  vim.keymap.set('i', '<C-n>', '<C-x><C-u>', { buffer = state.prompt_buf, silent = true })
  
  
  -- C-c to close in normal mode
  vim.keymap.set('n', '<C-c>', function()
    M.close()
  end, { buffer = state.prompt_buf, silent = true })
  
  -- Override C-w prefix for window navigation
  vim.keymap.set('n', '<C-w>', function()
    handle_window_command()
  end, { buffer = state.prompt_buf, silent = true })
end

-- Setup keymaps for output buffer
local function setup_output_keymaps()
  -- C-c to close in normal mode
  vim.keymap.set('n', '<C-c>', function()
    M.close()
  end, { buffer = state.output_buf, silent = true })
  
  -- Override C-w prefix for window navigation
  vim.keymap.set('n', '<C-w>', function()
    handle_window_command()
  end, { buffer = state.output_buf, silent = true })
  
  -- Enter to rerun command at cursor
  vim.keymap.set('n', '<CR>', function()
    rerun_command_at_cursor()
  end, { buffer = state.output_buf, silent = true, desc = 'Rerun command at cursor' })
  
  -- dd to delete command and its output
  vim.keymap.set('n', 'dd', function()
    delete_command_at_cursor()
  end, { buffer = state.output_buf, silent = true, desc = 'Delete command and output' })
  
  -- Insert mode commands redirect to prompt window
  local function switch_to_prompt_insert()
    if state.prompt_win and vim.api.nvim_win_is_valid(state.prompt_win) then
      vim.api.nvim_set_current_win(state.prompt_win)
      vim.cmd('startinsert')
    end
  end
  
  local function switch_to_prompt_append()
    if state.prompt_win and vim.api.nvim_win_is_valid(state.prompt_win) then
      vim.api.nvim_set_current_win(state.prompt_win)
      -- Just use startinsert! which appends after cursor
      vim.cmd('startinsert!')
    end
  end
  
  local function switch_to_prompt_insert_end()
    if state.prompt_win and vim.api.nvim_win_is_valid(state.prompt_win) then
      vim.api.nvim_set_current_win(state.prompt_win)
      vim.cmd('normal! $')
      vim.cmd('startinsert!')
    end
  end
  
  local function switch_to_prompt_insert_start()
    if state.prompt_win and vim.api.nvim_win_is_valid(state.prompt_win) then
      vim.api.nvim_set_current_win(state.prompt_win)
      vim.cmd('normal! 0')
      vim.cmd('startinsert')
    end
  end
  
  local function switch_to_prompt_new_line()
    if state.prompt_win and vim.api.nvim_win_is_valid(state.prompt_win) then
      vim.api.nvim_set_current_win(state.prompt_win)
      clear_prompt()
      vim.cmd('startinsert!')
    end
  end
  
  -- Map insert mode keys to switch to prompt
  vim.keymap.set('n', 'i', switch_to_prompt_insert, { buffer = state.output_buf, silent = true, desc = 'Switch to prompt and insert' })
  vim.keymap.set('n', 'a', switch_to_prompt_append, { buffer = state.output_buf, silent = true, desc = 'Switch to prompt and append' })
  vim.keymap.set('n', 'I', switch_to_prompt_insert_start, { buffer = state.output_buf, silent = true, desc = 'Switch to prompt and insert at start' })
  vim.keymap.set('n', 'A', switch_to_prompt_insert_end, { buffer = state.output_buf, silent = true, desc = 'Switch to prompt and insert at end' })
  vim.keymap.set('n', 'o', switch_to_prompt_new_line, { buffer = state.output_buf, silent = true, desc = 'Switch to prompt with new line' })
  vim.keymap.set('n', 'O', switch_to_prompt_new_line, { buffer = state.output_buf, silent = true, desc = 'Switch to prompt with new line' })
  
  -- Command navigation (Vim-style)
  vim.keymap.set('n', ']c', jump_to_next_command, { buffer = state.output_buf, silent = true, desc = 'Jump to next command' })
  vim.keymap.set('n', '[c', jump_to_previous_command, { buffer = state.output_buf, silent = true, desc = 'Jump to previous command' })
  
  -- Command navigation (alternative: Ctrl keys for familiar command history feel)
  vim.keymap.set('n', '<C-n>', jump_to_next_command, { buffer = state.output_buf, silent = true, desc = 'Jump to next command' })
  vim.keymap.set('n', '<C-p>', jump_to_previous_command, { buffer = state.output_buf, silent = true, desc = 'Jump to previous command' })
end

-- Close floating command line
function M.close()
  
  -- Remember which window had focus before closing
  local current_win = vim.api.nvim_get_current_win()
  if current_win == state.prompt_win then
    state.last_focused_window = 'prompt'
  elseif current_win == state.output_win then
    state.last_focused_window = 'output'
  end
  
  if state.prompt_win and vim.api.nvim_win_is_valid(state.prompt_win) then
    vim.api.nvim_win_close(state.prompt_win, true)
    state.prompt_win = nil
  end
  
  if state.output_win and vim.api.nvim_win_is_valid(state.output_win) then
    vim.api.nvim_win_close(state.output_win, true)
    state.output_win = nil
  end
  
  -- Keep buffers alive, don't delete them
  -- This preserves history between open/close cycles
  
  state.is_open = false
  state.original_win = nil
  state.original_buf = nil
end

-- Open floating command line
function M.open()
  if state.is_open then return end
  
  -- Store original context
  state.original_win = vim.api.nvim_get_current_win()
  state.original_buf = vim.api.nvim_get_current_buf()
  
  -- Create buffers only if they don't exist or are invalid
  if not state.output_buf or not vim.api.nvim_buf_is_valid(state.output_buf) then
    create_output_buffer()
  end
  
  if not state.prompt_buf or not vim.api.nvim_buf_is_valid(state.prompt_buf) then
    create_prompt_buffer()
  end
  
  -- Create windows
  create_windows()
  
  -- Setup keymaps (needed each time since they're buffer-local)
  setup_prompt_keymaps()
  setup_output_keymaps()
  
  state.is_open = true
  
  -- Clear prompt for new command
  clear_prompt()
  
  -- Only start in insert mode if the prompt window has focus
  if state.last_focused_window == 'prompt' then
    vim.cmd('startinsert!')
  end
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