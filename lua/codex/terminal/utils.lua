local M = {}

function M.normalize_focus(focus)
  if focus == nil then
    return true
  end
  return focus
end

function M.parse_args(cmd)
  if type(cmd) == "table" then
    return cmd
  end
  local args = {}
  local in_quotes, escape_next, current = false, false, ""
  local function add()
    if #current > 0 then
      table.insert(args, current)
      current = ""
    end
  end

  for i = 1, #cmd do
    local char = cmd:sub(i, i)
    if escape_next then
      current = current .. ((char == '"' or char == "\\") and "" or "\\") .. char
      escape_next = false
    elseif char == "\\" and in_quotes then
      escape_next = true
    elseif char == '"' then
      in_quotes = not in_quotes
    elseif char:find("[ \t]") and not in_quotes then
      add()
    else
      current = current .. char
    end
  end
  add()
  return args
end

return M
