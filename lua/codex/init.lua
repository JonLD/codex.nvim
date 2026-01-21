local vim = vim
local installer = require 'codex.installer'
local state = require 'codex.state'
local terminal = require 'codex.terminal'

local M = {}

local config = {
  keymaps = {
    toggle = nil,
    quit = '<C-q>', -- Default: Ctrl+q to quit
  },
  border = 'single',
  width = 0.8,
  height = 0.8,
  cmd = 'codex',
  model = nil, -- Default to the latest model
  autoinstall = true,
  panel     = false,   -- if true, open Codex in a side-panel instead of floating window
  use_buffer = false,  -- if true, capture Codex stdout into a normal buffer instead of a terminal
  env = {},
  terminal = {
    provider = "auto",
    split_side = "right",
    split_width_percentage = 0.30,
    show_native_term_exit_tip = true,
    auto_close = false,
    snacks_win_opts = {},
  },
}

function M.setup(user_config)
  config = vim.tbl_deep_extend('force', config, user_config or {})
  terminal.setup(config.terminal, config.cmd, config.env)

  vim.api.nvim_create_user_command('Codex', function(opts)
    local cmd_args = opts.args and opts.args ~= '' and opts.args or nil
    M.toggle(cmd_args)
  end, { desc = 'Toggle Codex popup', nargs = '*' })

  vim.api.nvim_create_user_command('CodexSendSelected', function(opts)
    local buf = vim.api.nvim_get_current_buf()
    local file_path = vim.api.nvim_buf_get_name(buf)
    if file_path == '' then
      vim.notify('[codex.nvim] No file path for current buffer.', vim.log.levels.WARN)
      return
    end

    local line1 = opts.line1
    local line2 = opts.line2
    if not opts.range or opts.range == 0 then
      local cur = vim.api.nvim_win_get_cursor(0)[1]
      line1 = cur
      line2 = cur
    end

    if line1 > line2 then
      line1, line2 = line2, line1
    end

    local rel_path = vim.fn.fnamemodify(file_path, ':.')
    if rel_path == '' then
      rel_path = file_path
    end

    local ref = string.format('@%s:%d-%d', rel_path, line1, line2)
    terminal.send_input(ref)
  end, { desc = 'Send selected lines to Codex via @file:line-line', range = true })

  if config.keymaps.toggle then
    vim.api.nvim_set_keymap('n', config.keymaps.toggle, '<cmd>Codex<CR>', { noremap = true, silent = true })
  end
end

local function open_window()
  local width = math.floor(vim.o.columns * config.width)
  local height = math.floor(vim.o.lines * config.height)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local styles = {
    single = {
      { '┌', 'FloatBorder' },
      { '─', 'FloatBorder' },
      { '┐', 'FloatBorder' },
      { '│', 'FloatBorder' },
      { '┘', 'FloatBorder' },
      { '─', 'FloatBorder' },
      { '└', 'FloatBorder' },
      { '│', 'FloatBorder' },
    },
    double = {
      { '╔', 'FloatBorder' },
      { '═', 'FloatBorder' },
      { '╗', 'FloatBorder' },
      { '║', 'FloatBorder' },
      { '╝', 'FloatBorder' },
      { '═', 'FloatBorder' },
      { '╚', 'FloatBorder' },
      { '║', 'FloatBorder' },
    },
    rounded = {
      { '╭', 'FloatBorder' },
      { '─', 'FloatBorder' },
      { '╮', 'FloatBorder' },
      { '│', 'FloatBorder' },
      { '╯', 'FloatBorder' },
      { '─', 'FloatBorder' },
      { '╰', 'FloatBorder' },
      { '│', 'FloatBorder' },
    },
    none = nil,
  }

  local border = type(config.border) == 'string' and styles[config.border] or config.border

  state.win = vim.api.nvim_open_win(state.buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = border,
  })
end

--- Open Codex in a side-panel (vertical split) instead of floating window
local function open_panel()
  -- Create a vertical split on the right and show the buffer
  vim.cmd('vertical rightbelow vsplit')
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, state.buf)
  -- Adjust width according to config (percentage of total columns)
  local width = math.floor(vim.o.columns * config.width)
  vim.api.nvim_win_set_width(win, width)
  state.win = win
end

function M.open(cmd_args)
  local function create_clean_buf()
    local buf = vim.api.nvim_create_buf(false, false)

    vim.api.nvim_buf_set_option(buf, 'bufhidden', 'hide')
    vim.api.nvim_buf_set_option(buf, 'swapfile', false)
    vim.api.nvim_buf_set_option(buf, 'filetype', 'codex')

    -- Apply configured quit keybinding

    if config.keymaps.quit then
      local quit_cmd = [[<cmd>lua require('codex').close()<CR>]]
      vim.api.nvim_buf_set_keymap(buf, 't', config.keymaps.quit, [[<C-\><C-n>]] .. quit_cmd, { noremap = true, silent = true })
      vim.api.nvim_buf_set_keymap(buf, 'n', config.keymaps.quit, quit_cmd, { noremap = true, silent = true })
    end

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
          if config.panel then open_panel() else open_window() end
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
      if config.panel then open_panel() else open_window() end
      return
    end
  end

  local function is_buf_reusable(buf)
    return type(buf) == 'number' and vim.api.nvim_buf_is_valid(buf)
  end

  if config.use_buffer then
    if not is_buf_reusable(state.buf) then
      state.buf = create_clean_buf()
    end

    if config.panel then open_panel() else open_window() end
  else
    terminal.open({}, cmd_args)
    return
  end

  if not state.job then
    -- assemble command
    local cmd_args = type(config.cmd) == 'string' and { config.cmd } or vim.deepcopy(config.cmd)
    if config.model then
      table.insert(cmd_args, '-m')
      table.insert(cmd_args, config.model)
    end
    if cmd_args and cmd_args ~= '' then
      local extra_args = vim.split(cmd_args, '%s+')
      for _, arg in ipairs(extra_args) do
        if arg ~= '' then
          table.insert(cmd_args, arg)
        end
      end
    end

    if config.use_buffer then
      -- capture stdout/stderr into normal buffer
      state.job = vim.fn.jobstart(cmd_args, {
        cwd = vim.loop.cwd(),
        stdout_buffered = true,
        on_stdout = function(_, data)
          if not data then return end
          for _, line in ipairs(data) do
            if line ~= '' then
              vim.api.nvim_buf_set_lines(state.buf, -1, -1, false, { line })
            end
          end
        end,
        on_stderr = function(_, data)
          if not data then return end
          for _, line in ipairs(data) do
            if line ~= '' then
              vim.api.nvim_buf_set_lines(state.buf, -1, -1, false, { '[ERR] ' .. line })
            end
          end
        end,
        on_exit = function(_, code)
          state.job = nil
          vim.api.nvim_buf_set_lines(state.buf, -1, -1, false, {
            ('[Codex exit: %d]'):format(code),
          })
        end,
      })
    else
      -- use a terminal buffer
      state.job = vim.fn.termopen(cmd_args, {
        cwd = vim.loop.cwd(),
        on_exit = function()
          state.job = nil
        end,
      })
    end
  end
end

function M.close()
  if config.use_buffer then
    if state.win and vim.api.nvim_win_is_valid(state.win) then
      vim.api.nvim_win_close(state.win, true)
    end
    state.win = nil
    return
  end
  terminal.close()
end

function M.toggle(cmd_args)
  if config.use_buffer then
    if state.win and vim.api.nvim_win_is_valid(state.win) then
      M.close()
    else
      M.open(cmd_args)
    end
    return
  end
  terminal.simple_toggle({}, cmd_args)
end

function M.statusline()
  if config.use_buffer then
    if state.job and not (state.win and vim.api.nvim_win_is_valid(state.win)) then
      return '[Codex]'
    end
    return ''
  end
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
