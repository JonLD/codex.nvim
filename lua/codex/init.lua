local vim = vim
local config_module = require 'codex.config'
local installer = require 'codex.installer'
local logger = require 'codex.logger'
local registry = require 'codex.registry'
local state = require 'codex.state'
local terminal = require 'codex.terminal'

local M = {}

M.version = {
  major = 0,
  minor = 1,
  patch = 0,
  prerelease = nil,
  string = function(self)
    local version = string.format("%d.%d.%d", self.major, self.minor, self.patch)
    if self.prerelease then
      version = version .. "-" .. self.prerelease
    end
    return version
  end,
}

M.state = {
  config = config_module.defaults,
  server = nil,
  port = nil,
  auth_token = nil,
  initialized = false,
}

function M.setup(user_config)
  local config = config_module.apply(user_config or {})
  M.state.config = config

  logger.setup(config)

  local term_config = vim.deepcopy(config.terminal or {})
  if config.shell ~= nil then
    term_config.shell = config.shell
  end
  terminal.setup(term_config, config.cmd, config.env)

  local diff = require("codex.diff")
  diff.setup(config)

  if config.auto_start then
    M.start(false)
  end

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

  vim.api.nvim_create_user_command("CodexStart", function()
    M.start()
  end, { desc = "Start Codex IDE integration" })

  vim.api.nvim_create_user_command("CodexStop", function()
    M.stop()
  end, { desc = "Stop Codex IDE integration" })

  vim.api.nvim_create_user_command("CodexStatus", function()
    if M.state.server and M.state.port then
      logger.info("command", "Codex IDE integration is running on port " .. tostring(M.state.port))
    else
      logger.info("command", "Codex IDE integration is not running")
    end
  end, { desc = "Show Codex IDE integration status" })

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("CodexShutdown", { clear = true }),
    callback = function()
      if M.state.server then
        M.stop()
      end
    end,
    desc = "Stop Codex IDE integration when exiting Neovim",
  })

  M.state.initialized = true
end

local function touch_registry()
  local ok = registry.touch()
  if not ok then
    logger.warn("registry", "Failed to update Neovim instance registry")
  end
end

local function open_panel(side)
  local placement = side == "left" and "topleft" or "botright"
  vim.cmd('vertical ' .. placement .. ' vsplit')
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, state.buf)
  -- Adjust width according to config (percentage of total columns)
  local width = math.floor(vim.o.columns * M.state.config.terminal.split_width_percentage)
  vim.api.nvim_win_set_width(win, width)
  state.win = win
end

function M.open(cmd_args)
  touch_registry()
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

  local config = M.state.config
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
  touch_registry()
  terminal.simple_toggle({}, cmd_args)
end

function M._format_path_for_at_mention(file_path)
  if not file_path or type(file_path) ~= "string" or file_path == "" then
    error("format_path_for_at_mention: file_path must be a non-empty string")
  end

  if not package.loaded["busted"] then
    if vim.fn.filereadable(file_path) == 0 and vim.fn.isdirectory(file_path) == 0 then
      error("format_path_for_at_mention: path does not exist: " .. file_path)
    end
  end

  local is_directory = vim.fn.isdirectory(file_path) == 1
  local formatted_path = file_path
  local cwd = vim.fn.getcwd()

  if string.find(file_path, cwd, 1, true) == 1 then
    local relative_path = string.sub(file_path, #cwd + 2)
    if relative_path ~= "" then
      formatted_path = relative_path
    else
      formatted_path = is_directory and "./" or file_path
    end
  end

  if is_directory and not string.match(formatted_path, "/$") then
    formatted_path = formatted_path .. "/"
  end

  return formatted_path, is_directory
end

function M.send_at_mention(file_path, start_line, end_line, context)
  context = context or "command"
  if not M.state.server then
    logger.error(context, "Codex IDE integration is not running")
    return false, "Codex IDE integration is not running"
  end

  local formatted_path, is_directory
  local format_ok, format_result, is_dir_result = pcall(M._format_path_for_at_mention, file_path)
  if not format_ok then
    return false, format_result
  end
  formatted_path, is_directory = format_result, is_dir_result

  if is_directory and (start_line or end_line) then
    start_line = nil
    end_line = nil
  end

  local params = {
    filePath = formatted_path,
    lineStart = start_line,
    lineEnd = end_line,
  }

  local broadcast_success = M.state.server.broadcast("at_mentioned", params)
  if not broadcast_success then
    local error_msg = "Failed to broadcast at_mention for " .. formatted_path
    logger.error(context, error_msg)
    return false, error_msg
  end

  return true, nil
end

function M.is_codex_connected()
  if not M.state.server then
    return false
  end

  local server_module = require("codex.server.init")
  local status = server_module.get_status()
  return status.running and status.client_count and status.client_count > 0
end

function M.start(show_startup_notification)
  if show_startup_notification == nil then
    show_startup_notification = true
  end
  if M.state.server then
    logger.warn("init", "Codex IDE integration is already running on port " .. tostring(M.state.port))
    return false, "Already running"
  end

  touch_registry()
  local server = require("codex.server.init")
  local lockfile = require("codex.lockfile")

  local auth_success, auth_token = pcall(lockfile.generate_auth_token)
  if not auth_success then
    local error_msg = "Failed to generate authentication token: " .. tostring(auth_token)
    logger.error("init", error_msg)
    return false, error_msg
  end

  local success, result = server.start(M.state.config, auth_token)
  if not success then
    local error_msg = "Failed to start Codex server: " .. tostring(result)
    logger.error("init", error_msg)
    return false, error_msg
  end

  M.state.server = server
  M.state.port = tonumber(result)
  M.state.auth_token = auth_token

  local lock_success, lock_result = lockfile.create(M.state.port, auth_token)
  if not lock_success then
    server.stop()
    M.state.server = nil
    M.state.port = nil
    M.state.auth_token = nil

    local error_msg = "Failed to create lock file: " .. tostring(lock_result)
    logger.error("init", error_msg)
    return false, error_msg
  end

  if M.state.config.track_selection then
    local selection = require("codex.selection")
    selection.enable(M.state.server, M.state.config.visual_demotion_delay_ms)
  end

  if show_startup_notification then
    logger.info("init", "Codex IDE integration started on port " .. tostring(M.state.port))
  end

  return true, M.state.port
end

function M.stop()
  if not M.state.server then
    logger.warn("init", "Codex IDE integration is not running")
    return false, "Not running"
  end

  local lockfile = require("codex.lockfile")
  local lock_success, lock_error = lockfile.remove(M.state.port)
  if not lock_success then
    logger.warn("init", "Failed to remove lock file: " .. tostring(lock_error))
  end

  if M.state.config.track_selection then
    local selection = require("codex.selection")
    selection.disable()
  end

  local success, error_msg = M.state.server.stop()
  if not success then
    logger.error("init", "Failed to stop Codex integration: " .. tostring(error_msg))
    return false, error_msg
  end

  M.state.server = nil
  M.state.port = nil
  M.state.auth_token = nil

  logger.info("init", "Codex IDE integration stopped")
  return true
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
