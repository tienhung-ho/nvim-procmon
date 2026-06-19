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

-- Render the most recent `width` samples as block-char columns.
-- `sep` (optional) is placed between columns so the bars read as distinct
-- columns instead of one solid blob. Output is left-padded with spaces to a
-- fixed visual width so the chart's right edge stays anchored.
function History:sparkline(width, sep)
  sep = sep or ""
  local sep_cells = vim.fn.strchars(sep)
  local full_cells = width + math.max(0, width - 1) * sep_cells

  local n = #self.buf
  if n == 0 then
    return string.rep(" ", full_cells)
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
  local bar = table.concat(chars, sep)
  -- left-pad with spaces if fewer samples than width
  local visible = #recent + math.max(0, #recent - 1) * sep_cells
  local pad = full_cells - visible
  if pad > 0 then
    bar = string.rep(" ", pad) .. bar
  end
  return bar
end

return History
