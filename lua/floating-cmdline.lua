local M = {}

-- Configuration
local config = {
  width_ratio = 0.8,  -- Width relative to screen
  height_ratio = 0.6, -- Height relative to screen for output window
  border = 'rounded', -- Border style
  output_highlight = 'Comment', -- Highlight group for output lines
  error_highlight = 'ErrorMsg', -- Highlight group for error lines
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

-- Setup highlight groups for our custom syntax
local function setup_highlights()
  -- Define highlight links for our syntax groups (can be customized by user)
  vim.api.nvim_set_hl(0, 'floatingcmdCommand', { link = 'Statement', default = true })
  vim.api.nvim_set_hl(0, 'floatingcmdOutput', { link = config.output_highlight, default = true })
  vim.api.nvim_set_hl(0, 'floatingcmdError', { link = config.error_highlight, default = true })
end

-- Create terminal buffer
local function create_buffer()
  state.buf = vim.api.nvim_create_buf(false, true)
  
  vim.api.nvim_buf_set_option(state.buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(state.buf, 'filetype', 'floatingcmd')  -- Custom filetype for controlled highlighting
  vim.api.nvim_buf_set_option(state.buf, 'bufhidden', 'hide')  -- Keep buffer when window closes
  vim.api.nvim_buf_set_option(state.buf, 'swapfile', false)
  vim.api.nvim_buf_set_option(state.buf, 'buflisted', false)
  
  -- Set up custom command completion
  vim.api.nvim_buf_set_option(state.buf, 'completefunc', 'v:lua.floating_cmdline_complete')
  
  -- Disable Copilot for this buffer
  vim.api.nvim_buf_set_var(state.buf, 'copilot_enabled', false)
  
  vim.api.nvim_buf_set_name(state.buf, '[Floating Command Line]')
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
    title = ' Command Line ',
    title_pos = 'center',
  })
  
  -- Window options
  vim.api.nvim_win_set_option(state.win, 'wrap', true)
  vim.api.nvim_win_set_option(state.win, 'scrolloff', 0)
end

-- Append content to buffer
local function append_to_buffer(lines, is_error)
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end
  
  -- Get current content
  local current_lines = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
  
  -- If buffer only contains one empty line, replace it instead of appending
  if #current_lines == 1 and current_lines[1] == '' then
    current_lines = {}
  end
  
  -- Track where new lines start for highlighting
  local start_line = #current_lines
  
  -- Append new lines
  for _, line in ipairs(lines) do
    table.insert(current_lines, line)
  end
  
  -- Update buffer
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, current_lines)
  
  -- With custom syntax, we don't need manual highlighting anymore
  -- The syntax file handles it automatically
  
  -- Scroll to bottom if window is valid
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    local line_count = #current_lines
    vim.api.nvim_win_set_cursor(state.win, {line_count, 0})
  end
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

-- Get metadata from output (if it exists)
local function get_output_metadata(line_num)
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return nil, nil
  end
  
  local lines = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
  
  -- Check if the next line after the command is metadata
  if line_num < #lines then
    local next_line = lines[line_num + 1]
    if next_line and next_line:match('^  %-%-CMD:') then
      -- Extract original command from metadata
      local original_cmd = next_line:match('^  %-%-CMD:(.*)$')
      return original_cmd, line_num + 1
    end
  end
  
  return nil, nil
end

-- Clear output for commands that have been edited
local function clear_outdated_output()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end
  
  local lines = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
  local lines_to_delete = {}
  
  -- Scan through all lines to find commands with metadata
  for i = 1, #lines do
    local line = lines[i]
    -- Is this a command line (not indented, has content)?
    if line and not line:match('^%s%s') and line:match('%S') then
      local cmd = line:gsub('^%s*(.-)%s*$', '%1')
      local stored_cmd, metadata_line = get_output_metadata(i)
      
      if stored_cmd then
        -- This command has output with metadata
        if cmd ~= stored_cmd then
          -- Command has been edited, mark its output for deletion
          local start_line, end_line = get_command_output_range(i)
          if start_line and end_line then
            table.insert(lines_to_delete, {start = start_line, end_line = end_line})
          end
        end
      end
    end
  end
  
  -- Delete outdated output from bottom to top to preserve line numbers
  for i = #lines_to_delete, 1, -1 do
    local range = lines_to_delete[i]
    vim.api.nvim_buf_set_lines(state.buf, range.start - 1, range.end_line, false, {})
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
  
  -- Replace the current line with the trimmed command (remove leading whitespace)
  if current_line ~= cmd then
    vim.api.nvim_buf_set_lines(state.buf, line_num - 1, line_num, false, {cmd})
  end
  
  -- Close any open completion popup
  if vim.fn.pumvisible() == 1 then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-e>', true, false, true), 'n', false)
  end
  
  -- Add to Vim's native command history
  vim.fn.histadd('cmd', cmd)
  
  -- First, delete any existing output for this command
  local start_line, end_line = get_command_output_range(line_num)
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
  
  -- Check if our window and buffer are still valid (command might have destroyed them)
  if not vim.api.nvim_buf_is_valid(state.buf) or not vim.api.nvim_win_is_valid(state.win) then
    -- Buffer or window was destroyed by the command, bail out
    state.buf = nil
    state.win = nil
    state.is_open = false
    return
  end
  
  -- Switch back to our window
  vim.api.nvim_set_current_win(state.win)
  
  -- Process output and prepare lines to insert
  local output_lines = {}
  if not ok then
    table.insert(output_lines, '  Error: ' .. result)  -- Error with indent
  elseif result and result ~= '' then
    for line in result:gmatch('[^\r\n]+') do
      local trimmed = line:gsub('^%s*(.-)%s*$', '%1')
      if trimmed ~= '' then
        table.insert(output_lines, '  ' .. trimmed)
      end
    end
  end
  
  -- Add metadata as first line of output (if there is output)
  if #output_lines > 0 then
    table.insert(output_lines, 1, '  --CMD:' .. cmd)
  end
  
  -- Insert output directly after the command line
  if #output_lines > 0 then
    vim.api.nvim_buf_set_lines(state.buf, line_num, line_num, false, output_lines)
  end
  
  -- Move cursor to the line after the output (or stay on command if no output)
  local new_cursor_line = line_num + #output_lines + 1
  local total_lines = vim.api.nvim_buf_line_count(state.buf)
  
  -- If we're at the end of the buffer, add an empty line for the next command
  if new_cursor_line > total_lines then
    vim.api.nvim_buf_set_lines(state.buf, total_lines, total_lines, false, {''})
    vim.api.nvim_win_set_cursor(state.win, {total_lines + 1, 0})
  else
    vim.api.nvim_win_set_cursor(state.win, {new_cursor_line, 0})
  end
  
  -- Cancel any active completion before starting new line
  if vim.fn.pumvisible() == 1 then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-e>', true, false, true), 'n', false)
  end
end

-- Prepare for command entry (add new line at bottom)
local function prepare_command_line()
  -- Check if last line is already empty
  local total_lines = vim.api.nvim_buf_line_count(state.buf)
  local last_line = vim.api.nvim_buf_get_lines(state.buf, total_lines - 1, total_lines, false)[1] or ''
  
  -- Only add empty line if the last line is not empty
  if last_line:match('%S') then  -- Contains non-whitespace characters
    append_to_buffer({''}, false)  -- Empty line is not error output
    total_lines = vim.api.nvim_buf_line_count(state.buf)
  end
  
  -- Move cursor to the last line
  vim.api.nvim_win_set_cursor(state.win, {total_lines, 0})
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

-- Rerun command at cursor and replace its output
local function rerun_command_at_cursor()
  local cmd, cmd_line = get_command_at_cursor()
  if not cmd then
    return  -- Not on a command line
  end
  
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
  
  -- Check if our window and buffer are still valid (command might have destroyed them)
  if not vim.api.nvim_buf_is_valid(state.buf) or not vim.api.nvim_win_is_valid(state.win) then
    -- Buffer or window was destroyed by the command, bail out
    state.buf = nil
    state.win = nil
    state.is_open = false
    return
  end
  
  -- Switch back to our window
  vim.api.nvim_set_current_win(state.win)
  
  -- Insert new output after the command line
  local output_lines = {}
  local is_error = false
  if not ok then
    table.insert(output_lines, '  Error: ' .. result)
    is_error = true
  elseif result and result ~= '' then
    for line in result:gmatch('[^\r\n]+') do
      local trimmed = line:gsub('^%s*(.-)%s*$', '%1')
      if trimmed ~= '' then
        table.insert(output_lines, '  ' .. trimmed)
      end
    end
  end
  
  -- Add metadata as first line of output (if there is output)
  if #output_lines > 0 then
    table.insert(output_lines, 1, '  --CMD:' .. cmd)
  end
  
  -- Insert output after the command line
  if #output_lines > 0 then
    vim.api.nvim_buf_set_lines(state.buf, cmd_line, cmd_line, false, output_lines)
    
    -- With custom syntax, highlighting is handled automatically
  end
  
  -- Position cursor back on the command line
  vim.api.nvim_win_set_cursor(state.win, {cmd_line, 0})
end

-- Delete command at cursor and its output
local function delete_command_at_cursor()
  local cmd, cmd_line = get_command_at_cursor()
  if not cmd then
    return false  -- Not on a command line, return false to indicate nothing was deleted
  end
  
  -- Find the output range for this command
  local start_line, end_line = get_command_output_range(cmd_line)
  
  -- Determine what to delete
  local delete_start = cmd_line
  local delete_end = end_line or cmd_line
  
  -- Delete the command line and its output
  vim.api.nvim_buf_set_lines(state.buf, delete_start - 1, delete_end, false, {})
  
  -- Adjust cursor position
  local new_line_count = vim.api.nvim_buf_line_count(state.buf)
  local new_cursor_line = math.min(delete_start, new_line_count)
  if new_cursor_line < 1 then
    new_cursor_line = 1
  end
  vim.api.nvim_win_set_cursor(state.win, {new_cursor_line, 0})
  
  return true  -- Successfully deleted command and output
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
  -- Set up autocmds
  local augroup = vim.api.nvim_create_augroup('FloatingCommandLine', { clear = true })
  
  -- Detect command changes and clear outdated output
  vim.api.nvim_create_autocmd({'TextChanged', 'TextChangedI'}, {
    buffer = state.buf,
    group = augroup,
    callback = function()
      -- Use vim.schedule to avoid conflicts during editing
      vim.schedule(clear_outdated_output)
    end,
    desc = 'Clear output when commands change'
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
  
  -- Normal mode: Enter to rerun command at cursor
  vim.keymap.set('n', '<CR>', function()
    rerun_command_at_cursor()
  end, { buffer = state.buf, silent = true, desc = 'Rerun command at cursor' })
  
  -- Normal mode: dd to delete command and its output (or normal delete)
  vim.keymap.set('n', 'dd', function()
    -- Try to delete as a command first
    if not delete_command_at_cursor() then
      -- Not on a command line, use normal dd behavior
      vim.cmd('normal! dd')
    end
  end, { buffer = state.buf, silent = true, desc = 'Delete line (or command with output)' })
  
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
  
  -- Setup highlights
  setup_highlights()
  
  -- Create window
  create_window()
  
  -- Setup keymaps (needed each time since they're buffer-local)
  setup_keymaps()
  
  state.is_open = true
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
  vim.keymap.set('n', '|', M.open, { silent = true, desc = 'Open floating command line' })
end

return M
