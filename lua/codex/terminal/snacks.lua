---Snacks.nvim terminal provider for Codex.
---@module 'codex.terminal.snacks'

local M = {}

local snacks_available, Snacks = pcall(require, "snacks")
local utils = require("codex.terminal.utils")
local terminal = nil

---@return boolean
local function is_available()
  return snacks_available and Snacks and Snacks.terminal ~= nil
end

---@param term_instance table
---@param config table
local function setup_terminal_events(term_instance, config)
  if config.auto_close then
    local closed = false
    local function close_terminal(status)
      if closed then
        return
      end
      closed = true
      if status ~= nil and status ~= 0 then
        vim.notify("Codex exited with code " .. status .. ".", vim.log.levels.ERROR)
      end
      terminal = nil
      vim.schedule(function()
        term_instance:close({ buf = true })
        vim.cmd.checktime()
      end)
    end

    term_instance:on("TermClose", function()
      close_terminal(vim.v.event.status)
    end, { buf = true })

    if term_instance.buf then
      vim.api.nvim_create_autocmd("TermClose", {
        buffer = term_instance.buf,
        once = true,
        callback = function()
          close_terminal(vim.v.event.status)
        end,
      })
    end
  end

  term_instance:on("BufWipeout", function()
    terminal = nil
  end, { buf = true })
end

---@param config table
---@param env_table table
---@param focus boolean|nil
---@return table
local function build_opts(config, env_table, focus)
  focus = utils.normalize_focus(focus)

  local win_opts
  if config.window and config.window.position == "float" then
    local width = math.floor(vim.o.columns * (config.window.width or 0.8))
    local height = math.floor(vim.o.lines * (config.window.height or 0.8))
    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - width) / 2)
    win_opts = {
      relative = "editor",
      width = width,
      height = height,
      row = row,
      col = col,
      style = "minimal",
      border = config.window.border or "single",
    }
  else
    local position = config.split_side
    if config.window and (config.window.position == "left" or config.window.position == "right") then
      position = config.window.position
    end
    win_opts = {
      position = position,
      width = config.split_width_percentage,
      height = 0,
      relative = "editor",
    }
  end

  return {
    env = env_table,
    start_insert = focus,
    auto_insert = focus,
    auto_close = false,
    win = vim.tbl_deep_extend("force", win_opts, config.snacks_win_opts or {}),
  }
end

function M.setup()
end

---@param cmd string|table
---@param env_table table
---@param config table
---@param focus boolean|nil
function M.open(cmd, env_table, config, focus)
  if not is_available() then
    vim.notify("Snacks.nvim terminal provider selected but Snacks.terminal not available.", vim.log.levels.ERROR)
    return
  end

  focus = utils.normalize_focus(focus)

  if terminal and terminal:buf_valid() then
    if not terminal.win or not vim.api.nvim_win_is_valid(terminal.win) then
      terminal:toggle()
      if focus then
        terminal:focus()
        local term_buf_id = terminal.buf
        if term_buf_id and vim.api.nvim_buf_get_option(term_buf_id, "buftype") == "terminal" then
          if terminal.win and vim.api.nvim_win_is_valid(terminal.win) then
            vim.api.nvim_win_call(terminal.win, function()
              vim.cmd("startinsert")
            end)
          end
        end
      end
    else
      if focus then
        terminal:focus()
        local term_buf_id = terminal.buf
        if term_buf_id and vim.api.nvim_buf_get_option(term_buf_id, "buftype") == "terminal" then
          if terminal.win and vim.api.nvim_win_is_valid(terminal.win) then
            vim.api.nvim_win_call(terminal.win, function()
              vim.cmd("startinsert")
            end)
          end
        end
      end
    end
    return
  end

  local opts = build_opts(config, env_table, focus)
  local term_instance = Snacks.terminal.open(cmd, opts)
  if term_instance and term_instance:buf_valid() then
    setup_terminal_events(term_instance, config)
    terminal = term_instance
  else
    terminal = nil
    local error_details = {}
    if not term_instance then
      table.insert(error_details, "Snacks.terminal.open() returned nil")
    elseif not term_instance:buf_valid() then
      table.insert(error_details, "terminal instance is invalid")
      if term_instance.buf and not vim.api.nvim_buf_is_valid(term_instance.buf) then
        table.insert(error_details, "buffer is invalid")
      end
      if term_instance.win and not vim.api.nvim_win_is_valid(term_instance.win) then
        table.insert(error_details, "window is invalid")
      end
    end

    local context = string.format("cmd=%s, opts=%s", vim.inspect(cmd), vim.inspect(opts))
    local error_msg = string.format(
      "Failed to open Codex terminal using Snacks. Details: %s. Context: %s",
      table.concat(error_details, ", "),
      context
    )
    vim.notify(error_msg, vim.log.levels.ERROR)
  end
end

function M.close()
  if not is_available() then
    return
  end
  if terminal and terminal:buf_valid() then
    terminal:close()
  end
end

---@param cmd_string string
---@param env_table table
---@param config table
function M.simple_toggle(cmd_string, env_table, config)
  if not is_available() then
    vim.notify("Snacks.nvim terminal provider selected but Snacks.terminal not available.", vim.log.levels.ERROR)
    return
  end

  if terminal and terminal:buf_valid() and terminal:win_valid() then
    terminal:toggle()
  elseif terminal and terminal:buf_valid() and not terminal:win_valid() then
    terminal:toggle()
  else
    M.open(cmd_string, env_table, config)
  end
end

---@param cmd_string string
---@param env_table table
---@param config table
function M.focus_toggle(cmd_string, env_table, config)
  if not is_available() then
    vim.notify("Snacks.nvim terminal provider selected but Snacks.terminal not available.", vim.log.levels.ERROR)
    return
  end

  if terminal and terminal:buf_valid() and not terminal:win_valid() then
    terminal:toggle()
  elseif terminal and terminal:buf_valid() and terminal:win_valid() then
    local term_win_id = terminal.win
    local current_win_id = vim.api.nvim_get_current_win()

    if term_win_id == current_win_id then
      terminal:toggle()
    else
      vim.api.nvim_set_current_win(term_win_id)
      if terminal.buf and vim.api.nvim_buf_is_valid(terminal.buf) then
        if vim.api.nvim_buf_get_option(terminal.buf, "buftype") == "terminal" then
          vim.api.nvim_win_call(term_win_id, function()
            vim.cmd("startinsert")
          end)
        end
      end
    end
  else
    M.open(cmd_string, env_table, config)
  end
end

---@param cmd_string string
---@param env_table table
---@param config table
function M.toggle(cmd_string, env_table, config)
  M.simple_toggle(cmd_string, env_table, config)
end

---@return number|nil
function M.get_active_bufnr()
  if terminal and terminal:buf_valid() and terminal.buf then
    if vim.api.nvim_buf_is_valid(terminal.buf) then
      return terminal.buf
    end
  end
  return nil
end

---@return boolean
function M.is_available()
  return is_available()
end

---@return table|nil
function M._get_terminal_for_test()
  return terminal
end

return M
