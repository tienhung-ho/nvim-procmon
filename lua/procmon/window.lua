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
