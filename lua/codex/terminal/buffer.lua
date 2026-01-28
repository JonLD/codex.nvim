-- This file handles Codex terminal buffer identification and display adjustments.
---@module 'codex.terminal.buffer'

local M = {}

local CODEX_TERMINAL_VAR = "codex_terminal"
-- Label used for the Codex terminal header (icon + name combined).
local CODEX_DISPLAY_NAME = "󰆍 Codex"
-- Default key to return to the previous window from the Codex terminal.
local DEFAULT_UNFOCUS_KEY = "<C-]>"
-- Default terminal key sequence to return to the previous window.
local DEFAULT_UNFOCUS_MAPPING = "<C-\\><C-n><C-w>p"

-- Expose defaults for clearing Codex terminal focus to external callers.
M.unfocus_defaults = {
  key = DEFAULT_UNFOCUS_KEY,
  mapping = DEFAULT_UNFOCUS_MAPPING,
}

local function is_valid_buffer(bufnr)
  return type(bufnr) == "number" and vim.api.nvim_buf_is_valid(bufnr)
end

local function safe_get_buffer_name(bufnr)
  local ok, name = pcall(vim.api.nvim_buf_get_name, bufnr)
  if ok and type(name) == "string" then
    return name
  end
  return ""
end

local function buffer_name_includes_codex(buf_name)
  if buf_name == "" then
    return false
  end
  return buf_name:lower():find("codex", 1, true) ~= nil
end

local function read_codex_flag(bufnr)
  local ok, value = pcall(vim.api.nvim_buf_get_var, bufnr, CODEX_TERMINAL_VAR)
  if ok then
    return value == true
  end
  return false
end

local function set_codex_flag(bufnr)
  pcall(vim.api.nvim_buf_set_var, bufnr, CODEX_TERMINAL_VAR, true)
end

local function resolve_unfocus_key(opts)
  if type(opts) ~= "table" then
    return DEFAULT_UNFOCUS_KEY
  end
  if opts.unfocus_key == false or opts.unfocus_key == "" then
    return nil
  end
  if type(opts.unfocus_key) == "string" then
    return opts.unfocus_key
  end
  return DEFAULT_UNFOCUS_KEY
end

local function resolve_unfocus_mapping(opts)
  if type(opts) ~= "table" then
    return DEFAULT_UNFOCUS_MAPPING
  end
  if type(opts.unfocus_mapping) == "string" and opts.unfocus_mapping ~= "" then
    return opts.unfocus_mapping
  end
  return DEFAULT_UNFOCUS_MAPPING
end

local function set_unfocus_keymap(bufnr, opts)
  if not (vim.keymap and vim.keymap.set) then
    return
  end

  local unfocus_key = resolve_unfocus_key(opts)
  if not unfocus_key then
    return
  end
  local unfocus_mapping = resolve_unfocus_mapping(opts)

  -- Map keys to return from terminal mode and move to the previous window.
  pcall(vim.keymap.set, "t", unfocus_key, unfocus_mapping, {
    buffer = bufnr,
    noremap = true,
    silent = true,
    desc = "Codex: return to previous window from terminal",
  })
end

---Mark Codex terminal buffers and adjust listing/display names.
---@param bufnr number
---@param opts table|nil
---@return boolean
function M.mark_terminal_buffer(bufnr, opts)
  if not is_valid_buffer(bufnr) then
    return false
  end

  -- Set buffer-local vars and hide from listings.
  set_codex_flag(bufnr)
  vim.bo[bufnr].buflisted = false

  local current_name = safe_get_buffer_name(bufnr)
  if current_name ~= CODEX_DISPLAY_NAME then
    pcall(vim.api.nvim_buf_set_name, bufnr, CODEX_DISPLAY_NAME)
  end
  -- Switch terminal-exit keymaps based on configuration.
  set_unfocus_keymap(bufnr, opts)

  return true
end

---Check whether a buffer is a Codex terminal buffer.
---@param bufnr number
---@return boolean
function M.is_codex_terminal_buffer(bufnr)
  if not is_valid_buffer(bufnr) then
    return false
  end

  if read_codex_flag(bufnr) then
    return true
  end

  local name = safe_get_buffer_name(bufnr)
  return buffer_name_includes_codex(name)
end

return M
