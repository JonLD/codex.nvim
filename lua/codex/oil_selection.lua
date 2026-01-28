-- This file builds file paths from oil.nvim entries.
---@module 'codex.oil_selection'
local M = {}

local function normalize_current_dir(current_dir)
  -- Normalize the current directory to always end with a slash.
  if not current_dir or current_dir == "" then
    return nil
  end

  if not current_dir:match("/$") then
    return current_dir .. "/"
  end

  return current_dir
end

local function build_path_from_entry(current_dir, entry)
  -- Build a full path from an oil.nvim entry.
  if not entry or type(entry) ~= "table" then
    return nil
  end

  if not entry.name or entry.name == "" then
    return nil
  end

  if entry.name == "." or entry.name == ".." then
    return nil
  end

  local full_path = current_dir .. entry.name

  if entry.type == "directory" and not full_path:match("/$") then
    full_path = full_path .. "/"
  end

  return full_path
end

function M.collect_paths_from_range(oil, bufnr, start_line, end_line)
  -- Collect oil.nvim entries from the specified line range.
  local dir_ok, current_dir = pcall(oil.get_current_dir, bufnr)
  if not dir_ok or not current_dir then
    return {}, "Failed to get current directory"
  end

  current_dir = normalize_current_dir(current_dir)
  if not current_dir then
    return {}, "Failed to get current directory"
  end

  local files = {}

  for line = start_line, end_line do
    local entry_ok, entry = pcall(oil.get_entry_on_line, bufnr, line)
    if entry_ok then
      local full_path = build_path_from_entry(current_dir, entry)
      if full_path then
        table.insert(files, full_path)
      end
    end
  end

  return files, nil
end

function M.collect_paths_from_cursor(oil, bufnr)
  -- Get the oil.nvim entry under the cursor.
  local entry_ok, entry = pcall(oil.get_cursor_entry)
  if not entry_ok or not entry then
    return {}, "Failed to get cursor entry"
  end

  local dir_ok, current_dir = pcall(oil.get_current_dir, bufnr)
  if not dir_ok or not current_dir then
    return {}, "Failed to get current directory"
  end

  current_dir = normalize_current_dir(current_dir)
  if not current_dir then
    return {}, "Failed to get current directory"
  end

  local full_path = build_path_from_entry(current_dir, entry)
  if not full_path then
    return {}, "No file found under cursor"
  end

  return { full_path }, nil
end

return M
