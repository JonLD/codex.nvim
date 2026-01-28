#!/usr/bin/env python3
import json
import keyword
import os
import re
import sys
import time
from typing import Any, Optional

import anyio
import pynvim
from fastmcp import FastMCP
from fastmcp.exceptions import ToolError

SERVER_NAME = "codex-nvim"
SERVER_VERSION = "0.1.0"
REGISTRY_PATH = os.path.expanduser("~/.codex/nvim_instances.json")
LOG_PATH = os.path.expanduser("~/.codex/codex-nvim-mcp.log")


def _log(message):
    try:
        with open(LOG_PATH, "a", encoding="utf-8") as log_file:
            log_file.write(f"{time.time():.0f} {message}\n")
    except Exception:
        pass


def _load_registry():
    if not os.path.exists(REGISTRY_PATH):
        return []
    try:
        with open(REGISTRY_PATH, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception:
        return []
    if isinstance(data, list):
        return data
    return []


def _select_instance(entries):
    candidates = [e for e in entries if isinstance(e, dict) and e.get("server")]
    if not candidates:
        return None
    return max(candidates, key=lambda e: e.get("last_seen", 0))


def _parse_address(addr):
    if addr.startswith("tcp://"):
        hostport = addr[len("tcp://"):]
        host, port_str = hostport.rsplit(":", 1)
        return "tcp", {"address": host, "port": int(port_str)}

    if addr.startswith("\\\\.\\pipe\\") or addr.startswith("\\.\\pipe\\"):
        return "socket", {"path": addr}

    if re.match(r"^[A-Za-z]:\\", addr):
        return "socket", {"path": addr}

    if ":" in addr:
        host, port_str = addr.rsplit(":", 1)
        if port_str.isdigit() and not os.path.exists(addr):
            return "tcp", {"address": host, "port": int(port_str)}

    return "socket", {"path": addr}


def _connect_nvim():
    last_error = None
    for _ in range(10):
        entries = _load_registry()
        instance = _select_instance(entries)
        if not instance:
            last_error = "No Neovim instance found in registry"
            time.sleep(0.3)
            continue
        addr = instance.get("server")
        transport, params = _parse_address(addr)
        sys.stderr.write(f"Connecting to Neovim at {addr}\n")
        sys.stderr.flush()
        _log(f"Connecting to Neovim at {addr}")
        try:
            return pynvim.attach(transport, **params)
        except Exception as exc:
            last_error = str(exc)
            time.sleep(0.3)
    raise RuntimeError(last_error or "Failed to connect to Neovim")


def _nvim_tools_list(nvim):
    return nvim.exec_lua("return require('codex.mcp_bridge').get_tool_list()", [])


def _nvim_call_tool(nvim, name, args, timeout_ms):
    response = nvim.exec_lua(
        "return require('codex.mcp_bridge').call_tool(...)",
        [name, args, timeout_ms],
    )
    if isinstance(response, dict) and response.get("_deferred") and response.get("key"):
        key = response["key"]
        deadline = time.time() + ((timeout_ms or 300000) / 1000.0)
        while time.time() < deadline:
            result = nvim.exec_lua(
                "return require('codex.mcp_bridge').poll_deferred(...)",
                [key],
            )
            if result is not None:
                return result
            time.sleep(0.05)
        return {
            "error": {
                "code": -32000,
                "message": "Tool execution timed out",
                "data": name,
            }
        }
    return response


def _schema_type_to_py(schema):
    if not isinstance(schema, dict):
        return Any
    schema_type = schema.get("type")
    if isinstance(schema_type, list):
        filtered = [t for t in schema_type if t != "null"]
        if len(filtered) == 1:
            schema_type = filtered[0]
        else:
            return Any
    if schema_type == "string":
        return str
    if schema_type == "integer":
        return int
    if schema_type == "number":
        return float
    if schema_type == "boolean":
        return bool
    if schema_type == "array":
        return list
    if schema_type == "object":
        return dict
    return Any


def _type_name(py_type, optional):
    if py_type is Any:
        return "Any"
    name = py_type.__name__ if hasattr(py_type, "__name__") else "Any"
    if optional:
        return f"Optional[{name}]"
    return name


def _format_default(value):
    if value is None:
        return "None"
    if isinstance(value, bool):
        return "True" if value else "False"
    if isinstance(value, (int, float)):
        return repr(value)
    return repr(value)


def _sanitize_identifier(name):
    sanitized = re.sub(r"\W", "_", str(name))
    if not sanitized:
        sanitized = "param"
    if sanitized[0].isdigit():
        sanitized = f"param_{sanitized}"
    if sanitized.startswith("_"):
        sanitized = f"param{sanitized}"
    if keyword.iskeyword(sanitized):
        sanitized = f"{sanitized}_"
    return sanitized


def _build_tool_function(tool_name, input_schema, description, call_tool):
    properties = {}
    required = set()
    if isinstance(input_schema, dict):
        props = input_schema.get("properties")
        if isinstance(props, dict):
            properties = props
        required_list = input_schema.get("required")
        if isinstance(required_list, list):
            required = set(required_list)

    param_defs = []
    mapping = []
    used_names = set()

    ordered_props = []
    for prop_name, prop_schema in properties.items():
        if not isinstance(prop_schema, dict):
            prop_schema = {}
        is_required = prop_name in required
        ordered_props.append((is_required, prop_name, prop_schema))

    ordered_props.sort(key=lambda item: (not item[0], item[1]))

    for is_required, prop_name, prop_schema in ordered_props:
        param_name = _sanitize_identifier(prop_name)
        base_name = param_name
        counter = 1
        while param_name in used_names:
            param_name = f"{base_name}_{counter}"
            counter += 1
        used_names.add(param_name)

        default_value = prop_schema.get("default") if not is_required else None
        if not is_required and "default" not in prop_schema:
            default_value = None

        py_type = _schema_type_to_py(prop_schema)
        optional_annotation = (not is_required) and default_value is None
        annotation = _type_name(py_type, optional_annotation)

        if is_required:
            param_defs.append(f"{param_name}: {annotation}")
        else:
            param_defs.append(f"{param_name}: {annotation} = {_format_default(default_value)}")

        mapping.append((param_name, prop_name, is_required))

    params_str = ", ".join(param_defs)
    safe_func = re.sub(r"[^0-9A-Za-z_]", "_", tool_name)
    func_name = f"_tool_{safe_func}"

    lines = [f"async def {func_name}({params_str}) -> dict:", "    args = {}"]
    for param_name, prop_name, is_required in mapping:
        if is_required:
            lines.append(f"    args[{prop_name!r}] = {param_name}")
        else:
            lines.append(f"    if {param_name} is not None:")
            lines.append(f"        args[{prop_name!r}] = {param_name}")
    lines.append(f"    return await anyio.to_thread.run_sync(_call_tool, {tool_name!r}, args)")

    source = "\n".join(lines)
    namespace = {
        "_call_tool": call_tool,
        "Any": Any,
        "Optional": Optional,
        "anyio": anyio,
    }
    exec(source, namespace)
    fn = namespace[func_name]
    fn.__doc__ = description or f"Proxy tool for {tool_name}"
    return fn


def _register_tools(nvim, mcp):
    tools = _nvim_tools_list(nvim) or []

    def call_tool(name, args):
        result = _nvim_call_tool(nvim, name, args, None)
        if isinstance(result, dict) and "error" in result:
            err = result.get("error")
            message = "Tool error"
            if isinstance(err, dict):
                message = err.get("message") or message
                if err.get("data"):
                    message = f"{message}: {err.get('data')}"
            raise ToolError(message)
        if isinstance(result, dict) and "result" in result:
            return result["result"]
        return result

    for tool_def in tools:
        if not isinstance(tool_def, dict):
            continue
        name = tool_def.get("name")
        if not isinstance(name, str):
            continue
        description = tool_def.get("description") or ""
        input_schema = tool_def.get("inputSchema") or {}
        fn = _build_tool_function(name, input_schema, description, call_tool)
        mcp.tool(fn, name=name, description=description)


def main():
    try:
        nvim = _connect_nvim()
    except Exception as exc:
        sys.stderr.write("Failed to connect to Neovim: %s\n" % exc)
        sys.stderr.flush()
        sys.exit(1)

    mcp = FastMCP(name=SERVER_NAME, version=SERVER_VERSION)
    _register_tools(nvim, mcp)
    _log("FastMCP server initialized")
    mcp.run()


if __name__ == "__main__":
    main()
