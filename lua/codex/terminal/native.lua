---Native Neovim terminal provider for Codex.
---@module 'codex.terminal.native'

local M = {}

local utils = require("codex.terminal.utils")

local bufnr = nil
local winid = nil
local jobid = nil
local tip_shown = false

---@type table
local config = require("codex.terminal").defaults

local function cleanup_state()
  bufnr = nil
  winid = nil
  jobid = nil
end

local function is_valid()
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    cleanup_state()
    return false
  end

  if not winid or not vim.api.nvim_win_is_valid(winid) then
    local windows = vim.api.nvim_list_wins()
    for _, win in ipairs(windows) do
      if vim.api.nvim_win_get_buf(win) == bufnr then
        winid = win
        return true
      end
    end
    return true
  end

  return true
end

local function open_terminal(cmd, env_table, effective_config, focus)
  focus = utils.normalize_focus(focus)

  if is_valid() then
    if focus and winid and vim.api.nvim_win_is_valid(winid) then
      vim.api.nvim_set_current_win(winid)
      vim.cmd("startinsert")
    end
    return true
  end

  local original_win = vim.api.nvim_get_current_win()
  local win_config = effective_config.window or {}
  local is_float = win_config.position == "float"

  local new_winid
  if is_float then
    local width = math.floor(vim.o.columns * (win_config.width or 0.8))
    local height = math.floor(vim.o.lines * (win_config.height or 0.8))
    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - width) / 2)
    local border = win_config.border or "single"
    local buf = vim.api.nvim_create_buf(false, false)
    new_winid = vim.api.nvim_open_win(buf, true, {
      relative = "editor",
      width = width,
      height = height,
      row = row,
      col = col,
      style = "minimal",
      border = border,
    })
  else
    local split_side = effective_config.split_side
    if win_config.position == "left" or win_config.position == "right" then
      split_side = win_config.position
    end
    local width = math.floor(vim.o.columns * effective_config.split_width_percentage)
    local full_height = vim.o.lines
    local placement_modifier

    if split_side == "left" then
      placement_modifier = "topleft "
    else
      placement_modifier = "botright "
    end

    vim.cmd(placement_modifier .. width .. "vsplit")
    new_winid = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_height(new_winid, full_height)

    vim.api.nvim_win_call(new_winid, function()
      vim.cmd("enew")
    end)
  end

  local term_cmd_arg
  if type(cmd) == "table" then
    term_cmd_arg = cmd
  elseif type(cmd) == "string" and cmd:find(" ", 1, true) then
    term_cmd_arg = vim.split(cmd, " ", { plain = true, trimempty = false })
  else
    term_cmd_arg = { cmd }
  end

  jobid = vim.fn.termopen(term_cmd_arg, {
    env = env_table,
    on_exit = function(job_id)
      vim.schedule(function()
        if job_id == jobid then
          local current_winid = winid
          local current_bufnr = bufnr

          cleanup_state()

          if not effective_config.auto_close then
            return
          end

          if current_winid and vim.api.nvim_win_is_valid(current_winid) then
            if current_bufnr and vim.api.nvim_buf_is_valid(current_bufnr) then
              if vim.api.nvim_win_get_buf(current_winid) == current_bufnr then
                vim.api.nvim_win_close(current_winid, true)
              end
            else
              vim.api.nvim_win_close(current_winid, true)
            end
          end
        end
      end)
    end,
  })

  if not jobid or jobid == 0 then
    vim.notify("Failed to open native terminal.", vim.log.levels.ERROR)
    if new_winid and vim.api.nvim_win_is_valid(new_winid) then
      vim.api.nvim_win_close(new_winid, true)
    end
    vim.api.nvim_set_current_win(original_win)
    cleanup_state()
    return false
  end

  winid = new_winid
  bufnr = vim.api.nvim_get_current_buf()
  vim.bo[bufnr].bufhidden = "hide"

  if effective_config.auto_close then
    vim.api.nvim_create_autocmd("TermClose", {
      buffer = bufnr,
      once = true,
      callback = function()
        if winid and vim.api.nvim_win_is_valid(winid) then
          vim.api.nvim_win_close(winid, true)
        end
        cleanup_state()
      end,
    })
  end

  if focus then
    vim.api.nvim_set_current_win(winid)
    vim.cmd("startinsert")
  else
    vim.api.nvim_set_current_win(original_win)
  end

  if config.show_native_term_exit_tip and not tip_shown then
    vim.notify("Native terminal opened. Press Ctrl-\\ Ctrl-N to return to Normal mode.", vim.log.levels.INFO)
    tip_shown = true
  end

  return true
end

local function close_terminal()
  if is_valid() then
    if winid and vim.api.nvim_win_is_valid(winid) then
      vim.api.nvim_win_close(winid, true)
    end
    cleanup_state()
  end
end

local function focus_terminal()
  if is_valid() and winid and vim.api.nvim_win_is_valid(winid) then
    vim.api.nvim_set_current_win(winid)
    vim.cmd("startinsert")
  end
end

local function is_terminal_visible()
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end

  local windows = vim.api.nvim_list_wins()
  for _, win in ipairs(windows) do
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == bufnr then
      winid = win
      return true
    end
  end

  winid = nil
  return false
end

local function hide_terminal()
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) and winid and vim.api.nvim_win_is_valid(winid) then
    vim.api.nvim_win_close(winid, false)
    winid = nil
  end
end

local function show_hidden_terminal(effective_config, focus)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end

  if is_terminal_visible() then
    if focus then
      focus_terminal()
    end
    return true
  end

  local original_win = vim.api.nvim_get_current_win()
  local width = math.floor(vim.o.columns * effective_config.split_width_percentage)
  local full_height = vim.o.lines
  local placement_modifier

  if effective_config.split_side == "left" then
    placement_modifier = "topleft "
  else
    placement_modifier = "botright "
  end

  vim.cmd(placement_modifier .. width .. "vsplit")
  local new_winid = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_height(new_winid, full_height)

  vim.api.nvim_win_set_buf(new_winid, bufnr)
  winid = new_winid

  if focus then
    vim.api.nvim_set_current_win(winid)
    vim.cmd("startinsert")
  else
    vim.api.nvim_set_current_win(original_win)
  end

  return true
end

local function get_base_cmd()
  local cmd_from_config = config.terminal_cmd
  if type(cmd_from_config) == "table" then
    return cmd_from_config[1]
  end
  if type(cmd_from_config) == "string" and cmd_from_config ~= "" then
    local first = utils.parse_args(cmd_from_config)[1]
    if first and first ~= "" then
      return first
    end
  end
  return "codex"
end

local function find_existing_codex_terminal()
  local base_cmd = get_base_cmd()
  local buffers = vim.api.nvim_list_bufs()
  for _, buf in ipairs(buffers) do
    if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_option(buf, "buftype") == "terminal" then
      local buf_name = vim.api.nvim_buf_get_name(buf)
      if buf_name:find(base_cmd, 1, true) then
        local windows = vim.api.nvim_list_wins()
        for _, win in ipairs(windows) do
          if vim.api.nvim_win_get_buf(win) == buf then
            return buf, win
          end
        end
      end
    end
  end
  return nil, nil
end

---@param term_config table
function M.setup(term_config)
  config = term_config
end

---@param cmd string|table
---@param env_table table
---@param effective_config table
---@param focus boolean|nil
function M.open(cmd, env_table, effective_config, focus)
  focus = utils.normalize_focus(focus)

  if is_valid() then
    if not winid or not vim.api.nvim_win_is_valid(winid) then
      show_hidden_terminal(effective_config, focus)
    else
      if focus then
        focus_terminal()
      end
    end
  else
    local existing_buf, existing_win = find_existing_codex_terminal()
    if existing_buf and existing_win then
      bufnr = existing_buf
      winid = existing_win
      if focus then
        focus_terminal()
      end
    else
      if not open_terminal(cmd, env_table, effective_config, focus) then
        vim.notify("Failed to open Codex terminal using native fallback.", vim.log.levels.ERROR)
      end
    end
  end
end

function M.close()
  close_terminal()
end

---@param cmd string|table
---@param env_table table
---@param effective_config table
function M.simple_toggle(cmd, env_table, effective_config)
  local has_buffer = bufnr and vim.api.nvim_buf_is_valid(bufnr)
  local is_visible = has_buffer and is_terminal_visible()

  if is_visible then
    hide_terminal()
  else
    if has_buffer then
      if not show_hidden_terminal(effective_config, true) then
        vim.notify("Failed to show hidden Codex terminal.", vim.log.levels.ERROR)
      end
    else
      local existing_buf, existing_win = find_existing_codex_terminal()
      if existing_buf and existing_win then
        bufnr = existing_buf
        winid = existing_win
        focus_terminal()
      else
        if not open_terminal(cmd, env_table, effective_config) then
          vim.notify("Failed to open Codex terminal using native fallback.", vim.log.levels.ERROR)
        end
      end
    end
  end
end

---@param cmd string|table
---@param env_table table
---@param effective_config table
function M.focus_toggle(cmd, env_table, effective_config)
  local has_buffer = bufnr and vim.api.nvim_buf_is_valid(bufnr)
  local is_visible = has_buffer and is_terminal_visible()

  if has_buffer then
    if is_visible then
      local current_win_id = vim.api.nvim_get_current_win()
      if winid == current_win_id then
        hide_terminal()
      else
        focus_terminal()
      end
    else
      if not show_hidden_terminal(effective_config, true) then
        vim.notify("Failed to show hidden Codex terminal.", vim.log.levels.ERROR)
      end
    end
  else
    local existing_buf, existing_win = find_existing_codex_terminal()
    if existing_buf and existing_win then
      bufnr = existing_buf
      winid = existing_win
      local current_win_id = vim.api.nvim_get_current_win()
      if existing_win == current_win_id then
        hide_terminal()
      else
        focus_terminal()
      end
    else
      if not open_terminal(cmd, env_table, effective_config) then
        vim.notify("Failed to open Codex terminal using native fallback.", vim.log.levels.ERROR)
      end
    end
  end
end

---@param cmd string|table
---@param env_table table
---@param effective_config table
function M.toggle(cmd, env_table, effective_config)
  M.simple_toggle(cmd, env_table, effective_config)
end

---@return number|nil
function M.get_active_bufnr()
  if is_valid() then
    return bufnr
  end
  return nil
end

---@return boolean
function M.is_available()
  return true
end

return M
