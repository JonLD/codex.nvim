-- This file standardizes @mention range formatting and display strings.
---@module "codex.mention"

local M = {}

---Build a display range string.
---@param start_line number|nil 0-based start line
---@param end_line number|nil 0-based end line
---@return string range_text Line range for display, or empty string when invalid
function M.format_range(start_line, end_line)
  if type(start_line) ~= "number" or type(end_line) ~= "number" then
    return ""
  end

  local display_start = start_line + 1
  local display_end = end_line + 1
  if display_start == display_end then
    return tostring(display_start)
  end
  return string.format("%d-%d", display_start, display_end)
end

return M
