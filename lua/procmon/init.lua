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
