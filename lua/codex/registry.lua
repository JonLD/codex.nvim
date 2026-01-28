---@module 'codex.registry'

local M = {}

local function get_registry_path()
  return vim.fn.expand("~/.codex/nvim_instances.json")
end

local function ensure_registry_dir()
  local registry_path = get_registry_path()
  local dir = vim.fn.fnamemodify(registry_path, ":h")
  if dir == "" then
    return false
  end
  local ok = pcall(vim.fn.mkdir, dir, "p")
  return ok
end

local function read_registry()
  local registry_path = get_registry_path()
  if vim.fn.filereadable(registry_path) == 0 then
    return {}
  end
  local ok, content = pcall(vim.fn.readfile, registry_path)
  if not ok or not content then
    return {}
  end
  local json = table.concat(content, "\n")
  if json == "" then
    return {}
  end
  local ok_decode, data = pcall(vim.fn.json_decode, json)
  if not ok_decode or type(data) ~= "table" then
    return {}
  end
  return data
end

local function write_registry(entries)
  if not ensure_registry_dir() then
    return false
  end
  local registry_path = get_registry_path()
  local ok_encode, json = pcall(vim.fn.json_encode, entries)
  if not ok_encode or type(json) ~= "string" then
    return false
  end
  local ok_write = pcall(function()
    local file = io.open(registry_path, "w")
    if not file then
      return
    end
    file:write(json)
    file:close()
  end)
  return ok_write
end

local function ensure_server_address()
  local servername = vim.v.servername
  if servername and servername ~= "" then
    return servername
  end

  local sep = package.config:sub(1, 1)
  local run_dir = vim.fn.stdpath("run")
  if run_dir == "" then
    run_dir = vim.fn.stdpath("data")
  end
  local addr = run_dir .. sep .. "codex-nvim-" .. tostring(vim.fn.getpid())
  local ok, started = pcall(vim.fn.serverstart, addr)
  if ok and type(started) == "string" and started ~= "" then
    return started
  end

  return vim.v.servername
end

function M.touch()
  local server = ensure_server_address()
  if not server or server == "" then
    return false
  end

  local entries = read_registry()
  local now = os.time()
  local cwd = vim.fn.getcwd()
  local pid = vim.fn.getpid()

  local updated = false
  for _, entry in ipairs(entries) do
    if entry.server == server then
      entry.last_seen = now
      entry.cwd = cwd
      entry.pid = pid
      updated = true
      break
    end
  end

  if not updated then
    table.insert(entries, {
      server = server,
      last_seen = now,
      cwd = cwd,
      pid = pid,
    })
  end

  return write_registry(entries)
end

return M
