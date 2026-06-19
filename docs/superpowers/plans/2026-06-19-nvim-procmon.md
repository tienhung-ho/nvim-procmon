# nvim-procmon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A toggleable, always-on floating widget in Neovim's top-right corner showing the current nvim process's live CPU % and RAM, each with a severity-colored history sparkline, refreshing every 10s.

**Architecture:** Four focused Lua modules under `lua/procmon/`: `stats` (measure via `vim.uv`), `history` (rolling buffer + sparkline string), `window` (the float + colored rendering), and `init` (orchestrator: timer, config, commands). Pure logic (history/sparkline/formatting) is separated from side-effecting UI/timer code.

**Tech Stack:** Lua, Neovim 0.12.x API (`vim.uv`/libuv, `vim.api` floating windows, extmark highlights). No external dependencies.

## Global Constraints

- Target Neovim 0.12.x; use `vim.uv` (not the deprecated `vim.loop`).
- Measure the **current nvim process only** — never system-wide or other PIDs.
- No external/shelled-out commands; all metrics come from libuv in-process.
- No third-party plugin dependencies.
- Per user preference: no strict TDD. Verify by running in nvim; add minimal sanity tests only for pure functions.
- Default refresh interval 10000ms; default history 20 samples; default position top-right; default keymap `<leader>m`; auto_start true; border rounded.

---

### Task 1: `history.lua` — rolling buffer + sparkline (pure)

**Files:**
- Create: `lua/procmon/history.lua`
- Test: `tests/history_spec.lua`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `History.new(capacity: integer) -> History` (default capacity 20 if nil)
  - `h:push(value: number)` — appends; drops oldest when over capacity
  - `h:values() -> number[]` — oldest→newest
  - `h:sparkline(width: integer) -> string` — `width` block chars `▁▂▃▄▅▆▇█`, right-aligned to newest, auto-scaled to current min/max. Empty buffer → string of `width` spaces. All-equal values → all mid-level (`▄`). Fewer samples than `width` → left-pad with spaces.

- [ ] **Step 1: Implement `history.lua`**

```lua
local BLOCKS = { "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" }

local History = {}
History.__index = History

function History.new(capacity)
  return setmetatable({ cap = capacity or 20, buf = {} }, History)
end

function History:push(value)
  table.insert(self.buf, value)
  while #self.buf > self.cap do
    table.remove(self.buf, 1)
  end
end

function History:values()
  return vim.deepcopy(self.buf)
end

function History:sparkline(width)
  local n = #self.buf
  if n == 0 then
    return string.rep(" ", width)
  end
  -- take the most recent `width` samples
  local start = math.max(1, n - width + 1)
  local recent = {}
  for i = start, n do
    recent[#recent + 1] = self.buf[i]
  end
  local lo, hi = math.huge, -math.huge
  for _, v in ipairs(recent) do
    lo = math.min(lo, v)
    hi = math.max(hi, v)
  end
  local span = hi - lo
  local chars = {}
  for _, v in ipairs(recent) do
    local idx
    if span == 0 then
      idx = 4 -- mid-level when all equal
    else
      idx = math.floor((v - lo) / span * 7 + 0.5) + 1
    end
    chars[#chars + 1] = BLOCKS[idx]
  end
  local bar = table.concat(chars)
  -- left-pad with spaces if fewer samples than width
  local pad = width - #recent
  if pad > 0 then
    bar = string.rep(" ", pad) .. bar
  end
  return bar
end

return History
```

- [ ] **Step 2: Write minimal sanity test**

```lua
-- tests/history_spec.lua
-- Run with: nvim -l tests/history_spec.lua
local History = dofile("lua/procmon/history.lua")

local function eq(a, b, msg)
  assert(a == b, (msg or "") .. " expected " .. vim.inspect(b) .. " got " .. vim.inspect(a))
end

-- capacity is respected
local h = History.new(3)
h:push(1); h:push(2); h:push(3); h:push(4)
eq(#h:values(), 3, "capacity")
eq(h:values()[1], 2, "oldest dropped")

-- empty buffer -> spaces
eq(History.new(5):sparkline(4), "    ", "empty sparkline")

-- ascending values -> last char is full block, first is lowest
local a = History.new(8)
for i = 1, 8 do a:push(i) end
local s = a:sparkline(8)
eq(vim.fn.strcharpart(s, 7, 1), "█", "max is full block")
eq(vim.fn.strcharpart(s, 0, 1), "▁", "min is low block")

-- all-equal -> mid level
local e = History.new(3)
e:push(5); e:push(5); e:push(5)
eq(e:sparkline(3), "▄▄▄", "all equal mid")

print("history_spec OK")
```

- [ ] **Step 3: Run test, verify it passes**

Run: `cd /Users/hohung/github.com/nvim-procmon && nvim -l tests/history_spec.lua`
Expected: prints `history_spec OK`, exit 0.

- [ ] **Step 4: Commit**

```bash
git add lua/procmon/history.lua tests/history_spec.lua
git commit -m "feat: add history ring buffer with sparkline rendering"
```

---

### Task 2: `stats.lua` — measure nvim process CPU % + RSS

**Files:**
- Create: `lua/procmon/stats.lua`
- Test: `tests/stats_spec.lua`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `stats.read() -> { cpu_pct: number, rss_bytes: integer }`
    - `rss_bytes` from `vim.uv.resident_set_memory()`
    - `cpu_pct` computed from delta of (user+sys CPU time) over wall time since previous `read()`. First call returns `cpu_pct = 0`.
  - `stats.format_ram(bytes: integer) -> string` — human-readable, e.g. `148M`, `1.2G`, `512K` (pure).

- [ ] **Step 1: Implement `stats.lua`**

```lua
local M = {}

local prev -- { cpu_seconds = number, wall_ns = number }

local function cpu_seconds()
  local ru = vim.uv.getrusage()
  local u = ru.utime.sec + ru.utime.usec / 1e6
  local s = ru.stime.sec + ru.stime.usec / 1e6
  return u + s
end

function M.read()
  local rss = vim.uv.resident_set_memory()
  local now_cpu = cpu_seconds()
  local now_wall = vim.uv.hrtime() -- nanoseconds

  local cpu_pct = 0
  if prev then
    local cpu_delta = now_cpu - prev.cpu_seconds
    local wall_delta = (now_wall - prev.wall_ns) / 1e9
    if wall_delta > 0 then
      cpu_pct = cpu_delta / wall_delta * 100
      if cpu_pct < 0 then cpu_pct = 0 end
    end
  end
  prev = { cpu_seconds = now_cpu, wall_ns = now_wall }

  return { cpu_pct = cpu_pct, rss_bytes = rss }
end

function M.format_ram(bytes)
  local units = { "B", "K", "M", "G" }
  local size = bytes
  local i = 1
  while size >= 1024 and i < #units do
    size = size / 1024
    i = i + 1
  end
  if i >= 3 and size < 100 then
    return string.format("%.1f%s", size, units[i]) -- e.g. 1.2G
  end
  return string.format("%d%s", math.floor(size + 0.5), units[i])
end

return M
```

- [ ] **Step 2: Write minimal sanity test**

```lua
-- tests/stats_spec.lua
-- Run with: nvim -l tests/stats_spec.lua
local stats = dofile("lua/procmon/stats.lua")

local function eq(a, b, msg)
  assert(a == b, (msg or "") .. " expected " .. tostring(b) .. " got " .. tostring(a))
end

-- format_ram
eq(stats.format_ram(512), "512B", "bytes")
eq(stats.format_ram(2048), "2K", "kilobytes")
eq(stats.format_ram(148 * 1024 * 1024), "148M", "megabytes")
eq(stats.format_ram(1610612736), "1.5G", "gigabytes")

-- read() returns a sane table; first call cpu_pct == 0
local r = stats.read()
assert(type(r.rss_bytes) == "number" and r.rss_bytes > 0, "rss positive")
eq(r.cpu_pct, 0, "first cpu_pct is 0")

-- second call returns a number (>= 0)
local r2 = stats.read()
assert(type(r2.cpu_pct) == "number" and r2.cpu_pct >= 0, "cpu_pct numeric")

print("stats_spec OK")
```

- [ ] **Step 3: Run test, verify it passes**

Run: `cd /Users/hohung/github.com/nvim-procmon && nvim -l tests/stats_spec.lua`
Expected: prints `stats_spec OK`, exit 0.

- [ ] **Step 4: Commit**

```bash
git add lua/procmon/stats.lua tests/stats_spec.lua
git commit -m "feat: add process CPU% and RSS measurement via vim.uv"
```

---

### Task 3: `window.lua` — top-right float with colored line rendering

**Files:**
- Create: `lua/procmon/window.lua`

**Interfaces:**
- Consumes: nothing (highlight groups are created in Task 4 / init; window only references group names by string).
- Produces:
  - `window.open(opts)` where `opts = { border: string, width: integer, height: integer }`
  - `window.close()`
  - `window.is_open() -> boolean`
  - `window.render(lines)` where `lines: { { text: string, hl: string? } [] } []` — a list of rows; each row is a list of segments `{ text, hl }`. Concatenates segments into the buffer line and applies `hl` (a highlight group name) to each segment's byte range via extmarks. `nil` hl means no highlight. Reopens the window if it was closed externally.

- [ ] **Step 1: Implement `window.lua`**

```lua
local M = {}

local state = { buf = nil, win = nil, ns = vim.api.nvim_create_namespace("procmon") }

local function buf_valid()
  return state.buf and vim.api.nvim_buf_is_valid(state.buf)
end

local function win_valid()
  return state.win and vim.api.nvim_win_is_valid(state.win)
end

local function ensure_buf()
  if not buf_valid() then
    state.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[state.buf].bufhidden = "hide"
    vim.bo[state.buf].filetype = "procmon"
  end
end

local function win_config(opts)
  return {
    relative = "editor",
    anchor = "NE",
    row = 1,
    col = vim.o.columns - 1,
    width = opts.width,
    height = opts.height,
    style = "minimal",
    border = opts.border,
    focusable = false,
    noautocmd = true,
    zindex = 50,
  }
end

function M.open(opts)
  ensure_buf()
  if win_valid() then
    return
  end
  state.win = vim.api.nvim_open_win(state.buf, false, win_config(opts))
  state.opts = opts
  vim.wo[state.win].winblend = 0
end

function M.close()
  if win_valid() then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win = nil
end

function M.is_open()
  return win_valid()
end

function M.render(rows)
  ensure_buf()
  if not win_valid() and state.opts then
    M.open(state.opts) -- reopen if closed externally
  end
  local lines = {}
  for _, segs in ipairs(rows) do
    local parts = {}
    for _, seg in ipairs(segs) do
      parts[#parts + 1] = seg.text
    end
    lines[#lines + 1] = table.concat(parts)
  end
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(state.buf, state.ns, 0, -1)
  for r, segs in ipairs(rows) do
    local col = 0
    for _, seg in ipairs(segs) do
      local bytes = #seg.text
      if seg.hl and bytes > 0 then
        vim.api.nvim_buf_set_extmark(state.buf, state.ns, r - 1, col, {
          end_col = col + bytes,
          hl_group = seg.hl,
        })
      end
      col = col + bytes
    end
  end
end

return M
```

- [ ] **Step 2: Manual smoke test in nvim**

Run:
```bash
cd /Users/hohung/github.com/nvim-procmon
nvim --cmd "set rtp+=." -c "lua local w=require('procmon.window'); w.open({border='rounded',width=22,height=3}); w.render({ {{text=' PROCMON', hl='Title'}}, {{text=' CPU  2.4%  ', hl=nil},{text='▁▂▃▄▅▆▇█', hl='DiagnosticOk'}}, {{text=' RAM  148M', hl=nil}} })"
```
Expected: a rounded-border float appears top-right with three lines; `PROCMON` highlighted, the sparkline colored green. `:q` to exit (window is non-focusable; use `:qa!`).

- [ ] **Step 3: Commit**

```bash
git add lua/procmon/window.lua
git commit -m "feat: add top-right floating window with segment highlighting"
```

---

### Task 4: `init.lua` — orchestrator (config, timer, commands, severity colors)

**Files:**
- Create: `lua/procmon/init.lua`
- Create: `plugin/procmon.lua` (auto-setup with defaults on load)

**Interfaces:**
- Consumes:
  - `require("procmon.history").new`, `:push`, `:sparkline`
  - `require("procmon.stats").read`, `.format_ram`
  - `require("procmon.window").open/close/is_open/render`
- Produces:
  - `M.setup(opts)` — merges defaults, creates highlight groups, defines `:ProcmonToggle`, maps keymap, starts if `auto_start`.
  - `M.show()`, `M.hide()`, `M.toggle()`.

- [ ] **Step 1: Implement `init.lua`**

```lua
local History = require("procmon.history")
local stats = require("procmon.stats")
local window = require("procmon.window")

local M = {}

local defaults = {
  position = "top-right", -- reserved; window currently fixed top-right
  interval = 10000,
  history = 20,
  keymap = "<leader>m",
  auto_start = true,
  border = "rounded",
  thresholds = {
    cpu = { warn = 50, crit = 80 },     -- percent
    ram = { warn = 500, crit = 1024 },  -- MB
  },
}

local cfg
local timer
local cpu_hist, ram_hist
local SPARK_WIDTH = 11
local WIN_WIDTH = 24

local function severity(value, t)
  if value >= t.crit then return "ProcmonCrit" end
  if value >= t.warn then return "ProcmonWarn" end
  return "ProcmonGood"
end

local function create_highlights()
  vim.api.nvim_set_hl(0, "ProcmonGood", { fg = "#7ee787", default = true })
  vim.api.nvim_set_hl(0, "ProcmonWarn", { fg = "#e3b341", default = true })
  vim.api.nvim_set_hl(0, "ProcmonCrit", { fg = "#f85149", default = true })
  vim.api.nvim_set_hl(0, "ProcmonTitle", { fg = "#58a6ff", bold = true, default = true })
end

local function tick()
  local ok, err = pcall(function()
    local s = stats.read()
    local ram_mb = s.rss_bytes / (1024 * 1024)
    cpu_hist:push(s.cpu_pct)
    ram_hist:push(ram_mb)

    local cpu_hl = severity(s.cpu_pct, cfg.thresholds.cpu)
    local ram_hl = severity(ram_mb, cfg.thresholds.ram)

    local cpu_val = string.format("%5.1f%%", s.cpu_pct)
    local ram_val = string.format("%6s", stats.format_ram(s.rss_bytes))

    window.render({
      { { text = " PROCMON", hl = "ProcmonTitle" } },
      {
        { text = " CPU " },
        { text = cpu_val, hl = cpu_hl },
        { text = "  " },
        { text = cpu_hist:sparkline(SPARK_WIDTH), hl = cpu_hl },
      },
      {
        { text = " RAM " },
        { text = ram_val, hl = ram_hl },
        { text = "  " },
        { text = ram_hist:sparkline(SPARK_WIDTH), hl = ram_hl },
      },
    })
  end)
  if not ok then
    window.render({
      { { text = " PROCMON", hl = "ProcmonTitle" } },
      { { text = " CPU   --", hl = "ProcmonWarn" } },
      { { text = " RAM   --", hl = "ProcmonWarn" } },
    })
    vim.schedule(function() vim.notify("procmon tick error: " .. tostring(err), vim.log.levels.DEBUG) end)
  end
end

function M.show()
  if window.is_open() and timer then return end
  cpu_hist = cpu_hist or History.new(cfg.history)
  ram_hist = ram_hist or History.new(cfg.history)
  window.open({ border = cfg.border, width = WIN_WIDTH, height = 3 })
  tick()
  timer = vim.uv.new_timer()
  timer:start(cfg.interval, cfg.interval, vim.schedule_wrap(tick))
end

function M.hide()
  if timer then
    timer:stop()
    timer:close()
    timer = nil
  end
  window.close()
end

function M.toggle()
  if window.is_open() then
    M.hide()
  else
    M.show()
  end
end

function M.setup(opts)
  cfg = vim.tbl_deep_extend("force", defaults, opts or {})
  create_highlights()
  cpu_hist = History.new(cfg.history)
  ram_hist = History.new(cfg.history)

  vim.api.nvim_create_user_command("ProcmonToggle", function() M.toggle() end, {})
  if cfg.keymap then
    vim.keymap.set("n", cfg.keymap, M.toggle, { desc = "Toggle procmon widget" })
  end

  if cfg.auto_start then
    vim.schedule(M.show)
  end
end

return M
```

- [ ] **Step 2: Implement `plugin/procmon.lua`**

```lua
-- Auto-initialize with defaults. Users can re-call require("procmon").setup{...}.
if vim.g.loaded_procmon then
  return
end
vim.g.loaded_procmon = true

require("procmon").setup({})
```

- [ ] **Step 3: Manual end-to-end test in nvim**

Run:
```bash
cd /Users/hohung/github.com/nvim-procmon
nvim --cmd "set rtp+=."
```
Expected:
- A rounded float appears top-right within a moment showing `PROCMON`, `CPU`, `RAM` lines with colored values.
- After ~10s (and as you edit/move around), the sparklines populate from the left and update.
- `:ProcmonToggle` (or `<leader>m`) hides it; running again shows it.
- `:qa!` to exit.

- [ ] **Step 4: Commit**

```bash
git add lua/procmon/init.lua plugin/procmon.lua
git commit -m "feat: add orchestrator with timer, commands, and severity colors"
```

---

### Task 5: README + final verification

**Files:**
- Create: `README.md`

**Interfaces:**
- Consumes: the public API from Task 4 (`setup`, `toggle`).
- Produces: nothing (docs only).

- [ ] **Step 1: Write `README.md`**

```markdown
# nvim-procmon

A tiny always-on floating widget for Neovim that shows **this nvim process's**
live CPU usage and memory (RSS), each with a severity-colored history
sparkline. Refreshes every 10s. Toggle off/on anytime.

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

Override highlight groups `ProcmonGood`, `ProcmonWarn`, `ProcmonCrit`,
`ProcmonTitle` to match your theme.
```

- [ ] **Step 2: Run both sanity tests**

Run:
```bash
cd /Users/hohung/github.com/nvim-procmon
nvim -l tests/history_spec.lua && nvim -l tests/stats_spec.lua
```
Expected: `history_spec OK` then `stats_spec OK`.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: add README"
```

---

## Self-Review Notes

- **Spec coverage:** process-only CPU+RSS (Task 2), sparklines ~3min/20 samples (Task 1), top-right float (Task 3), 10s timer + toggle command/keymap + auto_start (Task 4), severity colors green/yellow/red (Task 4), `pcall` error handling rendering `--` (Task 4), config defaults (Task 4), README (Task 5). All spec sections mapped.
- **Type consistency:** `History.new/push/values/sparkline`, `stats.read` returning `{cpu_pct, rss_bytes}` + `format_ram`, `window.open/close/is_open/render` with `rows` of `{text, hl}` segments — used consistently across Tasks 3–4.
- **Note:** `position` config is accepted but the window is currently fixed top-right (only supported anchor in scope). Documented in defaults comment.
