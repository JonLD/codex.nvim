---Terminal management for Codex with Snacks and native fallback.
---@module 'codex.terminal'

local utils = require("codex.terminal.utils")
local M = {}

---@type table
local defaults = {
  split_side = "right",
  split_width_percentage = 0.30,
  provider = "auto",
  show_native_term_exit_tip = true,
  terminal_cmd = nil,
  auto_close = false,
  env = {},
  snacks_win_opts = {},
}

M.defaults = defaults

local providers = {}

---@param provider_name string
---@return table|nil
local function load_provider(provider_name)
  if not providers[provider_name] then
    local ok, provider = pcall(require, "codex.terminal." .. provider_name)
    if ok then
      providers[provider_name] = provider
    else
      return nil
    end
  end
  return providers[provider_name]
end

---@param provider table
---@return table|nil
---@return string|nil
local function validate_and_enhance_provider(provider)
  if type(provider) ~= "table" then
    return nil, "Custom provider must be a table"
  end

  local required_functions = {
    "setup",
    "open",
    "close",
    "simple_toggle",
    "focus_toggle",
    "get_active_bufnr",
    "is_available",
  }

  for _, func_name in ipairs(required_functions) do
    local func = provider[func_name]
    if not func then
      return nil, "Custom provider missing required function: " .. func_name
    end
    local is_callable = type(func) == "function"
      or (type(func) == "table" and getmetatable(func) and getmetatable(func).__call)
    if not is_callable then
      return nil, "Custom provider field '" .. func_name .. "' must be callable, got: " .. type(func)
    end
  end

  local enhanced_provider = provider

  if not enhanced_provider.toggle then
    enhanced_provider.toggle = function(cmd_string, env_table, effective_config)
      return enhanced_provider.simple_toggle(cmd_string, env_table, effective_config)
    end
  end

  if not enhanced_provider._get_terminal_for_test then
    enhanced_provider._get_terminal_for_test = function()
      return nil
    end
  end

  return enhanced_provider, nil
end

---@return table
local function get_provider()
  if type(defaults.provider) == "table" then
    local custom_provider = defaults.provider
    local enhanced_provider = validate_and_enhance_provider(custom_provider)
    if enhanced_provider then
      local ok, is_available = pcall(enhanced_provider.is_available)
      if ok and is_available then
        return enhanced_provider
      end
    end
  elseif defaults.provider == "auto" then
    local snacks_provider = load_provider("snacks")
    if snacks_provider and snacks_provider.is_available() then
      return snacks_provider
    end
  elseif defaults.provider == "snacks" then
    local snacks_provider = load_provider("snacks")
    if snacks_provider and snacks_provider.is_available() then
      return snacks_provider
    end
    vim.notify("'snacks' provider configured, but Snacks.nvim not available. Falling back to 'native'.", vim.log.levels.WARN)
  elseif defaults.provider == "native" then
  elseif type(defaults.provider) == "string" then
    vim.notify("Invalid provider configured: " .. tostring(defaults.provider) .. ". Defaulting to 'native'.", vim.log.levels.WARN)
  else
    vim.notify("Invalid provider type: " .. type(defaults.provider) .. ". Defaulting to 'native'.", vim.log.levels.WARN)
  end

  local native_provider = load_provider("native")
  if not native_provider then
    error("codex.nvim: native terminal provider failed to load")
  end
  return native_provider
end

---@param opts_override table|nil
---@return table
local function build_config(opts_override)
  local effective_config = vim.deepcopy(defaults)
  if type(opts_override) == "table" then
    local validators = {
      split_side = function(val)
        return val == "left" or val == "right"
      end,
      split_width_percentage = function(val)
        return type(val) == "number" and val > 0 and val < 1
      end,
      snacks_win_opts = function(val)
        return type(val) == "table"
      end,
      auto_close = function(val)
        return type(val) == "boolean"
      end,
    }
    for key, val in pairs(opts_override) do
      if effective_config[key] ~= nil and validators[key] and validators[key](val) then
        effective_config[key] = val
      end
    end
  end
  return {
    split_side = effective_config.split_side,
    split_width_percentage = effective_config.split_width_percentage,
    auto_close = effective_config.auto_close,
    snacks_win_opts = effective_config.snacks_win_opts,
  }
end

---@param bufnr number|nil
---@return boolean
local function is_terminal_visible(bufnr)
  if not bufnr then
    return false
  end

  local bufinfo = vim.fn.getbufinfo(bufnr)
  return bufinfo and #bufinfo > 0 and #bufinfo[1].windows > 0
end

---@param cmd_args string|nil
---@return string|table
---@return table|nil
local function get_codex_command_and_env(cmd_args)
  local cmd_from_config = defaults.terminal_cmd
  local cmd
  if type(cmd_from_config) == "table" then
    cmd = vim.deepcopy(cmd_from_config)
    if cmd_args and cmd_args ~= "" then
      local extra_args = utils.parse_args(cmd_args)
      for _, arg in ipairs(extra_args) do
        table.insert(cmd, arg)
      end
    end
  else
    local base_cmd
    if type(cmd_from_config) == "string" and cmd_from_config ~= "" then
      base_cmd = cmd_from_config
    else
      base_cmd = "codex"
    end
    if cmd_args and cmd_args ~= "" then
      cmd = base_cmd .. " " .. cmd_args
    else
      cmd = base_cmd
    end
  end

  local env_table = {}
  for key, value in pairs(defaults.env or {}) do
    if type(key) == "string" and value ~= nil then
      env_table[key] = tostring(value)
    end
  end
  if vim.tbl_isempty(env_table) then
    env_table = nil
  end

  return cmd, env_table
end

---@param bufnr number|nil
---@return number|nil
local function get_terminal_job_id(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end
  local ok, job_id = pcall(vim.api.nvim_buf_get_var, bufnr, "terminal_job_id")
  if ok and type(job_id) == "number" then
    return job_id
  end
  return nil
end

---@param opts_override table|nil
---@param cmd_args string|nil
---@return boolean
local function ensure_terminal_visible_no_focus(opts_override, cmd_args)
  local provider = get_provider()

  if provider.ensure_visible then
    provider.ensure_visible()
    return true
  end

  local active_bufnr = provider.get_active_bufnr()
  if is_terminal_visible(active_bufnr) then
    return true
  end

  local effective_config = build_config(opts_override)
  local cmd, env_table = get_codex_command_and_env(cmd_args)

  provider.open(cmd, env_table, effective_config, false)
  return true
end

---@param user_term_config table|nil
---@param p_terminal_cmd string|table|nil
---@param p_env table|nil
function M.setup(user_term_config, p_terminal_cmd, p_env)
  if user_term_config == nil then
    user_term_config = {}
  elseif type(user_term_config) ~= "table" then
    vim.notify("codex.terminal.setup expects a table or nil for user_term_config", vim.log.levels.WARN)
    user_term_config = {}
  end

  if p_terminal_cmd == nil or type(p_terminal_cmd) == "string" or type(p_terminal_cmd) == "table" then
    defaults.terminal_cmd = p_terminal_cmd
  else
    vim.notify("codex.terminal.setup: Invalid terminal_cmd provided.", vim.log.levels.WARN)
    defaults.terminal_cmd = nil
  end

  if p_env == nil or type(p_env) == "table" then
    defaults.env = p_env or {}
  else
    vim.notify("codex.terminal.setup: Invalid env provided. Using empty table.", vim.log.levels.WARN)
    defaults.env = {}
  end

  for k, v in pairs(user_term_config) do
    if k == "terminal_cmd" then
    elseif defaults[k] ~= nil then
      if k == "split_side" and (v == "left" or v == "right") then
        defaults[k] = v
      elseif k == "split_width_percentage" and type(v) == "number" and v > 0 and v < 1 then
        defaults[k] = v
      elseif k == "provider" and (v == "snacks" or v == "native" or v == "auto" or type(v) == "table") then
        defaults[k] = v
      elseif k == "show_native_term_exit_tip" and type(v) == "boolean" then
        defaults[k] = v
      elseif k == "auto_close" and type(v) == "boolean" then
        defaults[k] = v
      elseif k == "snacks_win_opts" and type(v) == "table" then
        defaults[k] = v
      elseif k == "env" and type(v) == "table" then
        defaults[k] = v
      else
        vim.notify("codex.terminal.setup: Invalid value for " .. k .. ".", vim.log.levels.WARN)
      end
    else
      vim.notify("codex.terminal.setup: Unknown configuration key: " .. k, vim.log.levels.WARN)
    end
  end

  get_provider().setup(defaults)
end

---@param opts_override table|nil
---@param cmd_args string|nil
function M.open(opts_override, cmd_args)
  local effective_config = build_config(opts_override)
  local cmd, env_table = get_codex_command_and_env(cmd_args)

  get_provider().open(cmd, env_table, effective_config)
end

function M.close()
  get_provider().close()
end

---@param opts_override table|nil
---@param cmd_args string|nil
function M.simple_toggle(opts_override, cmd_args)
  local effective_config = build_config(opts_override)
  local cmd, env_table = get_codex_command_and_env(cmd_args)

  get_provider().simple_toggle(cmd, env_table, effective_config)
end

---@param opts_override table|nil
---@param cmd_args string|nil
function M.focus_toggle(opts_override, cmd_args)
  local effective_config = build_config(opts_override)
  local cmd, env_table = get_codex_command_and_env(cmd_args)

  get_provider().focus_toggle(cmd, env_table, effective_config)
end

---@param opts_override table|nil
---@param cmd_args string|nil
function M.toggle_open_no_focus(opts_override, cmd_args)
  ensure_terminal_visible_no_focus(opts_override, cmd_args)
end

---@param opts_override table|nil
---@param cmd_args string|nil
function M.ensure_visible(opts_override, cmd_args)
  ensure_terminal_visible_no_focus(opts_override, cmd_args)
end

---@param opts_override table|nil
---@param cmd_args string|nil
function M.toggle(opts_override, cmd_args)
  M.simple_toggle(opts_override, cmd_args)
end

---@return number|nil
function M.get_active_terminal_bufnr()
  return get_provider().get_active_bufnr()
end

---@param text string
---@param opts? {retries?: number, delay_ms?: number}
---@return boolean
function M.send_input(text, opts)
  local retries = (opts and opts.retries) or 15
  local delay_ms = (opts and opts.delay_ms) or 30
  local provider = get_provider()
  local bufnr = provider.get_active_bufnr()

  if not bufnr then
    M.open()
    bufnr = provider.get_active_bufnr()
  end

  local job_id = get_terminal_job_id(bufnr)
  if job_id then
    vim.api.nvim_chan_send(job_id, text .. "\n")
    return true
  end

  if retries <= 0 then
    vim.notify("Codex terminal is not ready to receive input.", vim.log.levels.WARN)
    return false
  end

  vim.defer_fn(function()
    M.send_input(text, { retries = retries - 1, delay_ms = delay_ms })
  end, delay_ms)
  return true
end

---@return table|nil
function M._get_managed_terminal_for_test()
  local provider = get_provider()
  if provider and provider._get_terminal_for_test then
    return provider._get_terminal_for_test()
  end
  return nil
end

return M
