local M = {}

-- History file path
local history_file = vim.fn.stdpath('data') .. '/command_history.json'

-- Command history storage
local command_history = {}

-- Load command history from file
local function load_history()
  local file = io.open(history_file, 'r')
  if file then
    local content = file:read('*a')
    file:close()
    local success, decoded = pcall(vim.json.decode, content)
    if success and decoded then
      command_history = decoded
    end
  end
end

-- Save command history to file
local function save_history()
  local file = io.open(history_file, 'w')
  if file then
    file:write(vim.json.encode(command_history))
    file:close()
  end
end

-- Update command usage in history
local function update_command_history(command)
  local now = os.time()
  if not command_history[command] then
    command_history[command] = {
      count = 0,
      last_used = now,
      first_used = now
    }
  end
  command_history[command].count = command_history[command].count + 1
  command_history[command].last_used = now
  save_history()
end

-- Get command score for sorting (frequency + recency)
local function get_command_score(command)
  local history = command_history[command]
  if not history then
    return 0
  end
  
  local now = os.time()
  local recency_weight = math.max(0, 1 - (now - history.last_used) / (7 * 24 * 60 * 60)) -- 7 days decay
  local frequency_weight = math.min(1, history.count / 10) -- Cap at 10 uses for max weight
  
  return recency_weight * 0.7 + frequency_weight * 0.3
end

-- Discover all available commands
local function get_all_commands()
  local commands = {}
  local seen_commands = {}
  
  -- Get all commands using vim.fn.getcompletion (includes built-ins and plugins)
  local all_command_names = vim.fn.getcompletion('', 'command')
  
  for _, name in ipairs(all_command_names) do
    if not seen_commands[name] then
      seen_commands[name] = true
      
      -- Try to get detailed info from API first
      local user_commands = vim.api.nvim_get_commands({})
      local buf_commands = vim.api.nvim_buf_get_commands(0, {})
      
      local details = user_commands[name] or buf_commands[name]
      
      if details then
        -- This is a user/plugin/buffer command with full details
        table.insert(commands, {
          name = name,
          description = details.definition or (details.script_id and ('Script: ' .. details.script_id)) or '',
          type = buf_commands[name] and 'buffer' or (details.script_id and 'plugin' or 'user'),
          nargs = details.nargs or '0',
          complete = details.complete,
          bang = details.bang,
          bar = details.bar,
          register = details.register
        })
      else
        -- This is a built-in command - we have limited info
        local description = ''
        -- Add descriptions for common commands
        local common_descriptions = {
          w = 'Write current buffer',
          write = 'Write current buffer',
          q = 'Quit current window',
          quit = 'Quit current window',
          wq = 'Write and quit',
          qa = 'Quit all',
          qall = 'Quit all',
          wqa = 'Write all and quit',
          wqall = 'Write all and quit',
          new = 'Create new window',
          vnew = 'Create new vertical window',
          tabnew = 'Create new tab',
          e = 'Edit file',
          edit = 'Edit file',
          sp = 'Split window horizontally',
          split = 'Split window horizontally',
          vs = 'Split window vertically',
          vsplit = 'Split window vertically',
          cd = 'Change directory',
          pwd = 'Print working directory',
          help = 'Show help',
          h = 'Show help',
          set = 'Set option',
          let = 'Set variable',
          echo = 'Echo expression',
          source = 'Source vim script',
          so = 'Source vim script',
          term = 'Open terminal',
          terminal = 'Open terminal',
        }
        description = common_descriptions[name] or ''
        
        table.insert(commands, {
          name = name,
          description = description,
          type = 'builtin',
          nargs = '*', -- Most built-in commands can take arguments
          complete = nil,
          bang = nil,
          bar = nil,
          register = nil
        })
      end
    end
  end
  
  return commands
end

-- Format command for display
local function format_command(cmd)
  local score = get_command_score(cmd.name)
  local usage_indicator = score > 0 and string.format(" (%.2f)", score) or ""
  local type_indicator = string.format("[%s]", cmd.type)
  
  return string.format(":%s %s%s %s", 
    cmd.name, 
    type_indicator,
    usage_indicator, 
    cmd.description
  )
end

-- Parse command and arguments from input
local function parse_command_input(input)
  local parts = vim.split(input:gsub("^%s+", ""), "%s+", { plain = false })
  local command_name = parts[1] or ""
  local args = {}
  
  for i = 2, #parts do
    table.insert(args, parts[i])
  end
  
  return command_name, args
end

-- Check if command accepts arguments
local function command_accepts_args(command_entry)
  -- Commands that explicitly take no arguments
  if command_entry.nargs == "0" then
    return false
  end
  
  -- Commands that typically don't take arguments
  local no_arg_commands = {
    w = true, write = true,
    q = true, quit = true,
    wq = true, qa = true, qall = true,
    pwd = true, wall = true,
    new = true, vnew = true, tabnew = true,
    term = true, terminal = true,
  }
  
  if no_arg_commands[command_entry.name] then
    return false
  end
  
  -- Most other commands can accept arguments
  return true
end

-- Execute selected command with arguments
local function execute_command(command_entry, args)
  update_command_history(command_entry.name)
  
  local cmd = ":" .. command_entry.name
  
  -- Add arguments if provided
  if args and #args > 0 then
    cmd = cmd .. " " .. table.concat(args, " ")
  end
  
  -- Always add space and enter for execution
  local cr = vim.api.nvim_replace_termcodes("<cr>", true, false, true)
  cmd = cmd .. cr
  
  vim.cmd("stopinsert")
  vim.api.nvim_feedkeys(cmd, "nt", false)
end


-- Get argument completions for a command
local function get_command_completions(command_name, current_arg)
  current_arg = current_arg or ""
  
  -- Try command-line completion first (works for plugins too!)
  local cmdline = command_name .. " " .. current_arg
  local completions = vim.fn.getcompletion(cmdline, 'cmdline')
  
  -- If cmdline completion worked, return it (this handles plugins automatically)
  if #completions > 0 then
    return completions
  end
  
  -- Fallback to specific completion types for built-in commands
  -- File completion for commands that typically take files
  local file_commands = {
    edit = true, e = true,
    split = true, sp = true,
    vsplit = true, vs = true,
    tabnew = true,
    write = true, w = true,
    source = true, so = true,
    read = true,
    saveas = true,
  }
  
  if file_commands[command_name] then
    return vim.fn.getcompletion(current_arg, 'file')
  end
  
  -- Help completion for help command
  if command_name == 'help' or command_name == 'h' then
    return vim.fn.getcompletion(current_arg, 'help')
  end
  
  -- Option completion for set command
  if command_name == 'set' then
    return vim.fn.getcompletion(current_arg, 'option')
  end
  
  return {}
end

-- Create argument completion picker with continue-editing support
local function create_argument_picker(command_name, current_args)
  local telescope = require('telescope')
  local pickers = require('telescope.pickers')
  local finders = require('telescope.finders')
  local conf = require('telescope.config').values
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  
  local current_arg = current_args[#current_args] or ""
  local completions = get_command_completions(command_name, current_arg)
  local has_completions = #completions > 0
  
  -- If no completions found, we'll handle this in the mappings
  if not has_completions then
    completions = {"<no completions available - press Enter to execute as-is>"}
  end
  
  -- Simple, clean title
  local title = string.format("Arguments for :%s (Enter=execute, Tab=continue editing)", command_name)
  
  pickers.new({}, {
    prompt_title = title,
    finder = finders.new_table({
      results = completions,
      entry_maker = function(completion)
        return {
          value = completion,
          display = completion,
          ordinal = completion,
        }
      end,
    }),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr, map)
      -- Tab to insert completion and continue editing
      map({"i", "n"}, "<Tab>", function()
        local selection = action_state.get_selected_entry()
        if has_completions and selection and not selection.value:find("<no completions available") then
          actions.close(prompt_bufnr)
          
          -- Build command so far with selected argument
          local args_so_far = vim.list_slice(current_args, 1, #current_args - 1)
          table.insert(args_so_far, selection.value)
          
          local command_so_far = command_name .. " " .. table.concat(args_so_far, " ")
          
          -- Restart command palette with the current command as initial prompt
          vim.defer_fn(function()
            M.command_palette_with_initial(command_so_far)
          end, 10)
        end
      end)
      
      -- Enter to execute immediately
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        
        if has_completions and selection and not selection.value:find("<no completions available") then
          -- Build final command with selected argument
          local final_args = vim.list_slice(current_args, 1, #current_args - 1)
          table.insert(final_args, selection.value)
          
          local final_cmd = ":" .. command_name .. " " .. table.concat(final_args, " ")
          local cr = vim.api.nvim_replace_termcodes("<cr>", true, false, true)
          
          update_command_history(command_name)
          vim.cmd("stopinsert")
          vim.api.nvim_feedkeys(final_cmd .. cr, "nt", false)
        else
          -- No completions available - execute with current args as-is
          local final_cmd = ":" .. command_name
          if current_args and #current_args > 0 then
            -- Remove the last empty argument we added for completion
            local actual_args = vim.list_slice(current_args, 1, #current_args - 1)
            if #actual_args > 0 then
              final_cmd = final_cmd .. " " .. table.concat(actual_args, " ")
            end
          end
          
          local cr = vim.api.nvim_replace_termcodes("<cr>", true, false, true)
          
          update_command_history(command_name)
          vim.cmd("stopinsert")
          vim.api.nvim_feedkeys(final_cmd .. cr, "nt", false)
        end
      end)
      return true
    end,
  }):find()
end

-- Command palette with initial prompt (for continuing after completion)
function M.command_palette_with_initial(initial_prompt)
  -- Load telescope modules on demand
  local telescope = require('telescope')
  local pickers = require('telescope.pickers')
  local finders = require('telescope.finders')
  local conf = require('telescope.config').values
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  
  -- Load history on each use to get latest data
  load_history()
  
  local all_commands = get_all_commands()
  
  -- Sort commands by score (most used/recent first)
  table.sort(all_commands, function(a, b)
    local score_a = get_command_score(a.name)
    local score_b = get_command_score(b.name)
    if score_a == score_b then
      return a.name < b.name -- alphabetical fallback
    end
    return score_a > score_b
  end)
  
  -- Create dynamic finder that filters based on arguments
  local dynamic_finder = finders.new_dynamic({
    fn = function(prompt)
      prompt = prompt or ""
      local command_name, args = parse_command_input(prompt)
      
      local filtered_commands = {}
      
      for _, cmd in ipairs(all_commands) do
        -- If arguments are provided, only show commands that accept arguments
        if #args > 0 then
          if command_accepts_args(cmd) then
            -- Only include commands that match the command name part
            if cmd.name:lower():find(command_name:lower(), 1, true) then
              table.insert(filtered_commands, {
                command = cmd,
                args = args,
                display_name = cmd.name .. " " .. table.concat(args, " ")
              })
            end
          end
        else
          -- No arguments provided, show all matching commands
          if cmd.name:lower():find(command_name:lower(), 1, true) then
            table.insert(filtered_commands, {
              command = cmd,
              args = {},
              display_name = cmd.name
            })
          end
        end
      end
      
      return filtered_commands
    end,
    entry_maker = function(entry)
      local cmd = entry.command
      local display = format_command(cmd)
      
      -- If we have args, show them in the display
      if #entry.args > 0 then
        display = string.format(":%s %s %s[%s] %s", 
          cmd.name,
          table.concat(entry.args, " "),
          string.format("[%s]", cmd.type),
          get_command_score(cmd.name) > 0 and string.format("%.2f", get_command_score(cmd.name)) or "",
          cmd.description
        )
      end
      
      return {
        value = entry,
        display = display,
        ordinal = entry.display_name .. ' ' .. cmd.description,
      }
    end,
  })
  
  pickers.new({}, {
    prompt_title = "Command Palette (Space for arguments, Enter to execute)",
    finder = dynamic_finder,
    sorter = conf.generic_sorter({}),
    default_text = initial_prompt,
    attach_mappings = function(prompt_bufnr, map)
      -- Space key to enter argument completion mode
      map("i", "<Space>", function()
        local current_prompt = action_state.get_current_line()
        local command_name, current_args = parse_command_input(current_prompt)
        
        -- If we have a partial command, try to get the full name from the selected entry
        local selection = action_state.get_selected_entry()
        if selection and selection.value and selection.value.command then
          command_name = selection.value.command.name
          current_args = {}
        end
        
        if command_name and command_name ~= "" then
          actions.close(prompt_bufnr)
          -- Add space to current args if we're continuing
          table.insert(current_args, "")
          create_argument_picker(command_name, current_args)
        else
          -- If no command yet, just insert space normally
          vim.api.nvim_feedkeys(" ", "nt", false)
        end
      end)
      
      actions.select_default:replace(function()
        local current_prompt = action_state.get_current_line()
        local command_name, current_args = parse_command_input(current_prompt)
        local selection = action_state.get_selected_entry()
        
        actions.close(prompt_bufnr)
        
        -- If we have a selection, use it; otherwise execute whatever was typed
        if selection then
          execute_command(selection.value.command, selection.value.args)
        elseif command_name and command_name ~= "" then
          -- Execute the typed command even if it's not in the list
          local final_cmd = ":" .. command_name
          if #current_args > 0 then
            final_cmd = final_cmd .. " " .. table.concat(current_args, " ")
          end
          
          local cr = vim.api.nvim_replace_termcodes("<cr>", true, false, true)
          
          update_command_history(command_name)
          vim.cmd("stopinsert")
          vim.api.nvim_feedkeys(final_cmd .. cr, "nt", false)
        end
      end)
      return true
    end,
  }):find()
end

-- Create command palette picker
function M.command_palette()
  -- Load telescope modules on demand
  local telescope = require('telescope')
  local pickers = require('telescope.pickers')
  local finders = require('telescope.finders')
  local conf = require('telescope.config').values
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  
  -- Load history on each use to get latest data
  load_history()
  
  local all_commands = get_all_commands()
  
  -- Sort commands by score (most used/recent first)
  table.sort(all_commands, function(a, b)
    local score_a = get_command_score(a.name)
    local score_b = get_command_score(b.name)
    if score_a == score_b then
      return a.name < b.name -- alphabetical fallback
    end
    return score_a > score_b
  end)
  
  -- Create dynamic finder that filters based on arguments
  local dynamic_finder = finders.new_dynamic({
    fn = function(prompt)
      prompt = prompt or ""
      local command_name, args = parse_command_input(prompt)
      
      local filtered_commands = {}
      
      for _, cmd in ipairs(all_commands) do
        -- If arguments are provided, only show commands that accept arguments
        if #args > 0 then
          if command_accepts_args(cmd) then
            -- Only include commands that match the command name part
            if cmd.name:lower():find(command_name:lower(), 1, true) then
              table.insert(filtered_commands, {
                command = cmd,
                args = args,
                display_name = cmd.name .. " " .. table.concat(args, " ")
              })
            end
          end
        else
          -- No arguments provided, show all matching commands
          if cmd.name:lower():find(command_name:lower(), 1, true) then
            table.insert(filtered_commands, {
              command = cmd,
              args = {},
              display_name = cmd.name
            })
          end
        end
      end
      
      return filtered_commands
    end,
    entry_maker = function(entry)
      local cmd = entry.command
      local display = format_command(cmd)
      
      -- If we have args, show them in the display
      if #entry.args > 0 then
        display = string.format(":%s %s %s[%s] %s", 
          cmd.name,
          table.concat(entry.args, " "),
          string.format("[%s]", cmd.type),
          get_command_score(cmd.name) > 0 and string.format("%.2f", get_command_score(cmd.name)) or "",
          cmd.description
        )
      end
      
      return {
        value = entry,
        display = display,
        ordinal = entry.display_name .. ' ' .. cmd.description,
      }
    end,
  })
  
  pickers.new({}, {
    prompt_title = "Command Palette (Space for arguments, Enter to execute)",
    finder = dynamic_finder,
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr, map)
      -- Space key to enter argument completion mode
      map("i", "<Space>", function()
        local current_prompt = action_state.get_current_line()
        local command_name, current_args = parse_command_input(current_prompt)
        
        -- If we have a partial command, try to get the full name from the selected entry
        local selection = action_state.get_selected_entry()
        if selection and selection.value and selection.value.command then
          command_name = selection.value.command.name
          current_args = {}
        end
        
        if command_name and command_name ~= "" then
          actions.close(prompt_bufnr)
          -- Add space to current args if we're continuing
          table.insert(current_args, "")
          create_argument_picker(command_name, current_args)
        else
          -- If no command yet, just insert space normally
          vim.api.nvim_feedkeys(" ", "nt", false)
        end
      end)
      
      actions.select_default:replace(function()
        local current_prompt = action_state.get_current_line()
        local command_name, current_args = parse_command_input(current_prompt)
        local selection = action_state.get_selected_entry()
        
        actions.close(prompt_bufnr)
        
        -- If we have a selection, use it; otherwise execute whatever was typed
        if selection then
          execute_command(selection.value.command, selection.value.args)
        elseif command_name and command_name ~= "" then
          -- Execute the typed command even if it's not in the list
          local final_cmd = ":" .. command_name
          if #current_args > 0 then
            final_cmd = final_cmd .. " " .. table.concat(current_args, " ")
          end
          
          local cr = vim.api.nvim_replace_termcodes("<cr>", true, false, true)
          
          update_command_history(command_name)
          vim.cmd("stopinsert")
          vim.api.nvim_feedkeys(final_cmd .. cr, "nt", false)
        end
      end)
      return true
    end,
  }):find()
end

-- Setup function
function M.setup(opts)
  opts = opts or {}
  
  -- Load initial history
  load_history()
  
  -- Create user command
  vim.api.nvim_create_user_command('CommandPalette', function()
    M.command_palette()
  end, { desc = 'Open command palette' })
end

return M