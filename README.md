# Codex Neovim Plugin
<img width="1480" alt="image" src="https://github.com/user-attachments/assets/eac126c5-e71c-4de9-817a-bf4e8f2f6af9" />

## A Neovim plugin integrating the open-sourced Codex CLI (`codex`)
> Latest version: ![GitHub tag (latest SemVer)](https://img.shields.io/github/v/tag/johnseth97/codex.nvim?sort=semver)

### Features:
- Toggle Codex window or side-panel with `:Codex`
- Background running when window hidden
- Statusline integration via `require("codex").status()`
- Pass Codex CLI args via `:Codex {args}`
- Reference files or selections with `:CodexReferenceFile`, `:CodexReferenceSelected`, and `:CodexSendSelected`
- Snacks.nvim provider support with native terminal fallback

### Installation:

- Prerequisite: install the Codex CLI and authenticate (log in or set an API key) before using the plugin.

lazy.nvim:
```lua
{
    "JonLD/codex.nvim",
    lazy = true,
    cmd = {
        "Codex",
        "CodexReferenceFile",
        "CodexReferenceSelected",
        "CodexSendSelected"
    },
    keys = {
        -- Your keymaps here
    },
    opts = {
        window     = {
            position = "right", -- "float", "left", or "right"
            border = "rounded", -- Options: "single", "double", or "rounded"
            width = 0.35,       -- Float width (0.0 to 1.0) or vertical split width percentage.
            height = 0.8,       -- Float height (0.0 to 1.0)
        },
        terminal   = {
            split_side = "right",
            split_width_percentage = 0.30,
            provider = "auto", -- "auto", "snacks", "native", or a custom provider table
            show_native_term_exit_tip = true,
            auto_close = false,
            snacks_win_opts = {},
        },
        env = {}, -- Extra env vars for the Codex CLI
        model       = nil,        -- Optional: pass a string to use a specific model (e.g., "o3-mini")
        autoinstall = false,       -- Automatically install the Codex CLI if not found
    },
}
```

### Keymaps:
```lua
keys = {
    { "<leader>a", nil, desc = "AI" },
    {
        "<C-z>", -- Change this to your preferred keybinding
        "<cmd>Codex<CR>",
        desc = "Toggle Codex popup or side-panel",
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
}
```

### Usage:
- Call `:Codex` to open or close the Codex terminal.
- Call `:Codex {args}` to pass arguments straight to the Codex CLI (for example `:Codex resume --last`).
- Add keys in your plugin spec (recommended).
- To choose floating popup vs side-panel, set `window.position = "float"` for a floating window or `"left"/"right"` for a split.
- Add the following code to show backgrounded Codex window in lualine:

```lua
require("codex").status() -- drop in to your lualine sections
```
- Use `:CodexReferenceFile` to send `@file` for the current buffer.
- Use `:CodexReferenceSelected` to send `@file:line-line` for the current selection (visual) or cursor line (normal).
- Use `:CodexSendSelected` to send `@file:line-line` plus the selected text (visual) or cursor line text (normal).
- Add `!` (bang) to `CodexReferenceFile`, `CodexReferenceSelected`, or `CodexSendSelected` to focus the Codex window after sending.

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
