-- This file collects small helper functions used across Codex.nvim.
---Shared utility functions for codex.nvim
---@module 'codex.utils'

local M = {}

---Normalizes focus parameter to default to true for backward compatibility
---@param focus boolean? The focus parameter
---@return boolean valid Whether the focus parameter is valid
function M.normalize_focus(focus)
  if focus == nil then
    return true
  else
    return focus
  end
end

return M
