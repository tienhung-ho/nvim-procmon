# nvim-procmon — Design

## Purpose

An always-on floating widget in the top-right corner of Neovim that shows the
**current Neovim process's** live CPU usage and memory (RSS), with mini history
sparklines colored by severity. Refreshes every 10 seconds and can be toggled
off.

## Scope

- Measures **this nvim process only** (not system-wide).
- Metrics: CPU % and resident memory (RSS).
- Always starts on launch; user can toggle it off/on.

Out of scope: disk usage, system-wide stats, per-thread breakdowns.

## Architecture

Four small modules under `lua/procmon/`, each with one clear job:

### `stats.lua` — measurement
- `read() -> { cpu_pct = number, rss_bytes = number }`
- RAM: `vim.uv.resident_set_memory()` (bytes).
- CPU %: `vim.uv.getrusage()` gives user+system CPU time. Keep the previous
  sample (cpu time + wall clock via `vim.uv.hrtime()`) in module state and
  compute `cpu_pct = cpu_time_delta / wall_time_delta * 100`.
- First call returns `cpu_pct = 0` (no previous sample yet).
- No knowledge of UI or history.

### `history.lua` — rolling buffer + sparkline
- Constructor `new(capacity)` (default capacity 20).
- `push(value)` — append, dropping the oldest when full.
- `values()` — current samples in order.
- `sparkline(width)` — returns a string of block chars `▁▂▃▄▅▆▇█`, auto-scaled
  to the min/max currently in the buffer. Pure and easily testable.
- Reused independently for the CPU buffer and the RAM buffer.

### `window.lua` — the float
- Owns a scratch buffer + a floating window pinned top-right.
- `open()`, `close()`, `is_open()`, `render(lines)` where `lines` is a list of
  `{ text, highlights }` so colors can be applied per segment.
- Uses `nvim_buf_add_highlight` (or extmarks) to color the sparkline segments.
- Border style configurable (default `rounded`). Window is non-focusable and
  does not steal the cursor.

### `init.lua` — orchestrator
- `setup(opts)` — merge config, create highlight groups, register
  `:ProcmonToggle`, optionally map keymap, and (if `auto_start`) `show()`.
- Owns a `vim.uv` timer at `interval` ms.
- Each tick (wrapped in `pcall`): `stats.read()` → push into CPU/RAM history →
  build colored lines → `window.render(lines)`.
- `show()` opens window + starts timer; `hide()` stops timer + closes window;
  `toggle()` switches between them.

## Display format

```
 PROCMON
 CPU  2.4%  ▁▁▂▃▂▅▇▆▄▂▁
 RAM  148M  ▃▃▃▄▄▅▅▆▆▇█
```

- Labels + current value, then a ~11-char sparkline.
- RAM formatted human-readable (KB/MB/GB).

## Color / severity

Three highlight groups, applied to the value text and sparkline:

- `ProcmonGood`  — green
- `ProcmonWarn`  — yellow
- `ProcmonCrit`  — red

Thresholds (configurable):
- CPU: <50% good, 50–80% warn, >80% crit.
- RAM: based on absolute MB, e.g. <500MB good, 500MB–1GB warn, >1GB crit.

Each sparkline bar is colored by that sample's severity, so the chart shades
from green toward red as load rises (mirrors the reference screenshot).

## Data flow

```
startup → setup() → show() → [timer 10s]
   tick → stats.read() → cpu_hist.push / ram_hist.push
        → format lines (value + sparkline + severity colors)
        → window.render(lines)
toggle() → hide() (stop timer + close) or show() (start + open)
```

## Configuration (`setup(opts)` defaults)

```lua
{
  position   = "top-right",
  interval   = 10000,        -- ms
  history    = 20,           -- samples (~3 min at 10s)
  keymap     = "<leader>m",  -- set to false to disable
  auto_start = true,
  border     = "rounded",
  thresholds = {
    cpu = { warn = 50, crit = 80 },        -- percent
    ram = { warn = 500, crit = 1024 },     -- MB
  },
}
```

## Error handling

- Whole tick body wrapped in `pcall`; on error, render `--` for the affected
  metric rather than killing the timer.
- If the window is closed externally (e.g. `:q`-ed), `render()` detects an
  invalid window and reopens or no-ops safely.

## Testing

Per user preference, no strict TDD on this small personal project. Verify by
loading the plugin in nvim and watching the widget update. `history.lua`'s
`sparkline()` and the RAM formatter are pure and can get quick sanity tests if
desired later.
