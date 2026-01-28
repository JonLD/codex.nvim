# Codex Neovim Plugin

## A Neovim plugin integrating Codex CLI

### Features:
- Toggle Codex terminal with `:Codex`
- Background running when terminal hidden
- Statusline integration via `require("codex").status()`
- Pass Codex CLI args via `:Codex {args}`
- Reference files or selections with `:CodexReferenceFile`, `:CodexReferenceSelected`, and `:CodexSendSelected`
- Snacks.nvim provider support with native terminal fallback
- IDE integration server for Codex CLI (MCP tools, diffs, selection)

### Installation:

- Prerequisite: install the Codex CLI and authenticate (log in or set an API key) before using the plugin.

lazy.nvim:
```lua
{
    "JonLD/codex.nvim",
    cmd = {
        "Codex",
        "CodexReferenceFile",
        "CodexReferenceSelected",
        "CodexSendSelected"
    },
    keys = {
        { "<leader>a", nil, desc = "AI" },
        {
            "<C-z>", -- Change to your preferred keybinding
            "<cmd>Codex<CR>",
            desc = "Toggle Codex terminal",
            mode = { "n", "t" },
        },
        {
            "<leader>ac",
            "<cmd>Codex resume --last<CR>",
            desc = "Codex continue (Resume last chat)",
        },
        {
            "<leader>ar",
            "<cmd>Codex resume<CR>",
            desc = "Resume Codex",
        },
        {
            "<leader>as",
            "<cmd>CodexReferenceSelected!<CR>",
            desc = "Send selection reference to Codex",
            mode = { "n", "v" },
        },
        {
            "<leader>at",
            "<cmd>CodexSendSelected!<CR>",
            desc = "Send selection with content to Codex",
            mode = { "n", "v" },
        },
        {
            "<leader>af",
            "<cmd>CodexReferenceFile!<CR>",
            desc = "Send file reference to Codex",
            mode = { "n", "v" },
        },
    },
    opts = {},
}
```

### Usage:
- Call `:Codex` to open or close the Codex terminal.
- Call `:Codex {args}` to pass arguments straight to the Codex CLI (for example `:Codex resume --last`).
- Add keys in your plugin spec (recommended).
- Use `:CodexStart`, `:CodexStop`, and `:CodexStatus` to control IDE integration.
- Add the following code to show backgrounded Codex terminal in lualine:

```lua
require("codex").status() -- drop in to your lualine sections
```
- Use `:CodexReferenceFile` to send `@file` for the current buffer.
- Use `:CodexReferenceSelected` to send `@file:line-line` for the current selection (visual) or cursor line (normal).
- Use `:CodexSendSelected` to send `@file:line-line` plus the selected text (visual) or cursor line text (normal).
- Add `!` (bang) to `CodexReferenceFile`, `CodexReferenceSelected`, or `CodexSendSelected` to focus the Codex terminal after sending.

### MCP Server (Codex CLI)
This plugin ships a Python MCP server that bridges Codex CLI to Neovim over RPC.
It binds to the most recent Neovim instance that ran `:Codex` or `:CodexStart`.
It records instances in `~/.codex/nvim_instances.json`.

Prerequisites:
```bash
uv sync
```

Register with Codex:
```bash
codex mcp add codex-nvim --command uv --args "run" "--python" "3.10" "--" "python" "C:\path\to\codex.nvim\mcp\codex_nvim_server.py"
```

If you launch Codex from a different working directory, set the MCP server cwd
to the plugin root in `~/.codex/config.toml` so `uv` can find `pyproject.toml`:

```toml
[mcp_servers.codex-nvim]
command = "uv"
args = ["run", "--python", "3.10", "--", "python", "C:\\path\\to\\codex.nvim\\mcp\\codex_nvim_server.py"]
cwd = "C:\\path\\to\\codex.nvim"
```

### Options:
Defaults:
```lua
opts = {
    auto_start = true,
    port_range = { min = 10000, max = 65535 },
    auth_mode = "optional", -- "required", "optional", or "disabled"
    log_level = "info",
    track_selection = true,
    terminal   = {
        split_side = "right",
        split_width_percentage = 0.30,
        provider = "auto", -- "auto", "snacks", "native", or a custom provider table
        show_native_term_exit_tip = true,
        auto_close = true,
        snacks_win_opts = {},
    },
    env = {}, -- Extra env vars for the Codex CLI
    model       = nil,        -- Optional: pass a string to use a specific model (e.g., "o3-mini")
    autoinstall = false,       -- Automatically install the Codex CLI if not found
}
```

### Configuration:
- All plugin configurations can be seen in the `opts` table of the plugin setup, as shown in the installation section.
- To run Codex via a shell wrapper (useful for Nu or other shells that require `-c`), you can set `shell` in your setup:

```lua
shell = {
    cmd = "nu",
    args = { "-c" },
    env = {
        WT_SESSION = vim.env.WT_SESSION,
        WT_PROFILE_ID = vim.env.WT_PROFILE_ID,
    },
}
```
This `shell.env` table is merged into the Codex process environment, so you can preserve terminal-specific variables (like Windows Terminal session/profile values) when launching Codex through a shell.
- You can set `cmd` to a string or table to override the Codex CLI command, and `env` to provide extra environment variables for the Codex process.

- **For deeper customization, please refer to the [Codex CLI documentation](https://github.com/openai/codex?tab=readme-ov-file#full-configuration-example) full configuration example. These features change quickly as Codex CLI is in active beta development.*

### Related Projects:
- Originally built from: https://github.com/johnseth97/codex.nvim
- Inspiration: https://github.com/coder/claudecode.nvim
