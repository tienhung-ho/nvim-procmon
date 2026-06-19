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
