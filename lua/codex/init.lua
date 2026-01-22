local vim = vim
local installer = require 'codex.installer'
local state = require 'codex.state'
local terminal = require 'codex.terminal'

local M = {}

local config = {
  cmd = 'codex',
  shell = nil,
  model = nil, -- Default to the latest model
  autoinstall = false,
  env = {},
  terminal = {
    provider = "auto",
    split_side = "right",
    split_width_percentage = 0.30,
    show_native_term_exit_tip = true,
    auto_close = true,
    snacks_win_opts = {},
  },
}

function M.setup(user_config)
  config = vim.tbl_deep_extend('force', config, user_config or {})
  local term_config = vim.deepcopy(config.terminal or {})
  if config.shell ~= nil then
    term_config.shell = config.shell
  end
  terminal.setup(term_config, config.cmd, config.env)

  vim.api.nvim_create_user_command('Codex', function(opts)
    local cmd_args = opts.args and opts.args ~= '' and opts.args or nil
    M.toggle(cmd_args)
  end, { desc = 'Toggle Codex terminal', nargs = '*' })

  local function current_buffer_rel_path()
    local buf = vim.api.nvim_get_current_buf()
    local file_path = vim.api.nvim_buf_get_name(buf)
    if file_path == '' then
      vim.notify('[codex.nvim] No file path for current buffer.', vim.log.levels.WARN)
      return nil
    end
    local rel_path = vim.fn.fnamemodify(file_path, ':.')
    if rel_path == '' then
      rel_path = file_path
    end
    return rel_path
  end

  local function resolve_range(opts)
    if opts.range and opts.range ~= 0 then
      return opts.line1, opts.line2
    end

    local mode = vim.fn.mode()
    if mode == 'v' or mode == 'V' or mode == '\22' then
      local start_pos = vim.api.nvim_buf_get_mark(0, '<')
      local end_pos = vim.api.nvim_buf_get_mark(0, '>')
      local line1 = start_pos[1]
      local line2 = end_pos[1]
      if line1 > 0 and line2 > 0 then
        return line1, line2
      end
    end

    local cur = vim.api.nvim_win_get_cursor(0)[1]
    return cur, cur
  end

  local function should_focus(opts)
    return opts.bang
  end

  vim.api.nvim_create_user_command('CodexReferenceFile', function(opts)
    local rel_path = current_buffer_rel_path()
    if not rel_path then
      return
    end
    terminal.send_input(string.format('@%s', rel_path), { append_string = '' })
    if should_focus(opts) then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'n', false)
      terminal.focus()
    end
  end, { desc = 'Reference current file in Codex via @file', bang = true })

  vim.api.nvim_create_user_command('CodexReferenceSelected', function(opts)
    local rel_path = current_buffer_rel_path()
    if not rel_path then
      return
    end
    local line1, line2 = resolve_range(opts)

    if line1 > line2 then
      line1, line2 = line2, line1
    end

    local ref
    if line1 == line2 then
      ref = string.format('@%s:%d', rel_path, line1)
    else
      ref = string.format('@%s:%d-%d', rel_path, line1, line2)
    end
    terminal.send_input(ref, { append_string = ' ' })
    if should_focus(opts) then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'n', false)
      terminal.focus()
    end
  end, { desc = 'Reference selected lines in Codex via @file:line-line', range = true, bang = true })

  vim.api.nvim_create_user_command('CodexSendSelected', function(opts)
    local rel_path = current_buffer_rel_path()
    if not rel_path then
      return
    end

    local line1, line2 = resolve_range(opts)

    if line1 > line2 then
      line1, line2 = line2, line1
    end

    local ref
    if line1 == line2 then
      ref = string.format('@%s:%d', rel_path, line1)
    else
      ref = string.format('@%s:%d-%d', rel_path, line1, line2)
    end
    local lines = vim.api.nvim_buf_get_lines(0, line1 - 1, line2, false)
    local text = table.concat(lines, '\n')
    terminal.send_input('\n' .. ref .. '\n' .. text)
    if should_focus(opts) then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'n', false)
      terminal.focus()
    end
  end, { desc = 'Send selected lines with @file:line-line reference to Codex', range = true, bang = true })

end

local function open_panel(side)
  local placement = side == "left" and "topleft" or "botright"
  vim.cmd('vertical ' .. placement .. ' vsplit')
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, state.buf)
  -- Adjust width according to config (percentage of total columns)
  local width = math.floor(vim.o.columns * config.terminal.split_width_percentage)
  vim.api.nvim_win_set_width(win, width)
  state.win = win
end

function M.open(cmd_args)
  local function create_clean_buf()
    local buf = vim.api.nvim_create_buf(false, false)

    vim.api.nvim_buf_set_option(buf, 'bufhidden', 'hide')
    vim.api.nvim_buf_set_option(buf, 'swapfile', false)
    vim.api.nvim_buf_set_option(buf, 'filetype', 'codex')

    return buf
  end

  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_set_current_win(state.win)
    return
  end

  local check_cmd = type(config.cmd) == 'string' and not config.cmd:find '%s' and config.cmd or (type(config.cmd) == 'table' and config.cmd[1]) or nil

  if check_cmd and vim.fn.executable(check_cmd) == 0 then
    if config.autoinstall then
      installer.prompt_autoinstall(function(success)
        if success then
          M.open() -- Try again after installing
        else
          -- Show failure message *after* buffer is created
          if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
            state.buf = create_clean_buf()
          end
          vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, {
            'Autoinstall cancelled or failed.',
            '',
            'You can install manually with:',
            '  npm install -g @openai/codex',
          })
          open_panel(config.terminal.split_side)
        end
      end)
      return
    else
      -- Show fallback message
      if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
        state.buf = vim.api.nvim_create_buf(false, false)
      end
      vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, {
        'Codex CLI not found, autoinstall disabled.',
        '',
        'Install with:',
        '  npm install -g @openai/codex',
        '',
        'Or enable autoinstall in setup: require("codex").setup{ autoinstall = true }',
      })
      open_panel(config.terminal.split_side)
      return
    end
  end

  terminal.open({}, cmd_args)
end

function M.close()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
    state.win = nil
    return
  end
  terminal.close()
end

function M.toggle(cmd_args)
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    M.close()
    return
  end
  terminal.simple_toggle({}, cmd_args)
end

function M.statusline()
  local bufnr = terminal.get_active_terminal_bufnr()
  if not bufnr then
    return ''
  end
  local bufinfo = vim.fn.getbufinfo(bufnr)
  local is_visible = bufinfo and #bufinfo > 0 and #bufinfo[1].windows > 0
  if is_visible then
    return ''
  end
  return '[Codex]'
end

function M.status()
  return {
    function()
      return M.statusline()
    end,
    cond = function()
      return M.statusline() ~= ''
    end,
    icon = '',
    color = { fg = '#51afef' },
  }
end

return setmetatable(M, {
  __call = function(_, opts)
    M.setup(opts)
    return M
  end,
})
