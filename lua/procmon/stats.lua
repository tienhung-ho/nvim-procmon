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
