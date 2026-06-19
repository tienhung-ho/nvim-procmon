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
