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
