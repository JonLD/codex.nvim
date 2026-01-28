---@module 'codex.mcp_bridge'

local M = {}

local tools_initialized = false

local function ensure_tools()
  local tools = require("codex.tools.init")
  if type(tools.get_tool_list) ~= "function" then
    error("codex.tools.init missing get_tool_list")
  end
  if not tools_initialized then
    tools.setup({})
    tools_initialized = true
  end
  return tools
end

function M.get_tool_list()
  local tools = ensure_tools()
  return tools.get_tool_list()
end

function M.call_tool(name, args, timeout_ms)
  local tools = ensure_tools()
  local params = {
    name = name,
    arguments = args or {},
  }

  local response = tools.handle_invoke(nil, params)
  if response and response._deferred and response.coroutine then
    local co_key = tostring(response.coroutine)

    if not _G.codex_deferred_responses then
      _G.codex_deferred_responses = {}
    end
    if not _G.codex_deferred_results then
      _G.codex_deferred_results = {}
    end

    _G.codex_deferred_responses[co_key] = function(res)
      _G.codex_deferred_results[co_key] = res
    end

    return { _deferred = true, key = co_key, timeout_ms = timeout_ms, tool = name }
  end

  return response
end

function M.poll_deferred(key)
  if not key then
    return nil
  end

  if not _G.codex_deferred_results then
    return nil
  end

  local result = _G.codex_deferred_results[key]
  if result ~= nil then
    _G.codex_deferred_results[key] = nil
    if _G.codex_deferred_responses then
      _G.codex_deferred_responses[key] = nil
    end
  end

  return result
end

return M
