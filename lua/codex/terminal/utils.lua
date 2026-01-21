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

function M.append_cmd_args(cmd_table, cmd_args)
  if type(cmd_table) ~= "table" or not cmd_args or cmd_args == "" then
    return cmd_table
  end

  local args = M.parse_args(cmd_args)
  if #args == 0 then
    return cmd_table
  end

  for i, value in ipairs(cmd_table) do
    if value == "-c" then
      local tail = table.concat(args, " ")
      if cmd_table[i + 1] then
        cmd_table[i + 1] = cmd_table[i + 1] .. " " .. tail
      else
        cmd_table[i + 1] = tail
      end
      return cmd_table
    end
  end

  for _, arg in ipairs(args) do
    table.insert(cmd_table, arg)
  end

  return cmd_table
end

return M
