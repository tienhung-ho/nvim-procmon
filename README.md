# nvim-procmon

A tiny always-on floating widget for Neovim that shows **this nvim process's**
live CPU usage and memory (RSS), each with a severity-colored history
sparkline. Refreshes every 10s. Toggle off/on anytime.

```
 PROCMON

 CPU   2.4%    ▂  ▅  ▃  ▆  ▇  █

 RAM   148M    ▃  ▄  ▅  ▆  ▇  █
```

## Requirements

- Neovim 0.12+ (uses `vim.uv`). No external dependencies.

## Install (lazy.nvim)

```lua
{
  dir = "~/github.com/nvim-procmon",
  config = function()
    require("procmon").setup({})
  end,
}
```

## Usage

- Appears top-right on startup (when `auto_start = true`).
- `:ProcmonToggle` or `<leader>m` to hide/show.

## Configuration (defaults)

```lua
require("procmon").setup({
  interval   = 10000,        -- refresh ms
  history    = 20,           -- samples kept for sparkline
  keymap     = "<leader>m",  -- false to disable
  auto_start = true,
  border     = "rounded",
  thresholds = {
    cpu = { warn = 50, crit = 80 },     -- percent
    ram = { warn = 500, crit = 1024 },  -- MB
  },
})
```

## Colors

The widget colors values and sparkline bars by severity (green → yellow →
red). Override the highlight groups `ProcmonGood`, `ProcmonWarn`,
`ProcmonCrit`, and `ProcmonTitle` to match your theme, e.g.:

```lua
vim.api.nvim_set_hl(0, "ProcmonWarn", { fg = "#ffaa00" })
```

## How it works

Metrics come straight from libuv in-process — `vim.uv.resident_set_memory()`
for RAM and `vim.uv.getrusage()` for CPU time (CPU % is the delta over the
refresh interval). No shelling out, measures only the current nvim process.
