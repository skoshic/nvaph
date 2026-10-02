local config = require("nvaph.config")
local util = require("nvaph.util")
local layout = require("nvaph.graph.layout")
local render = require("nvaph.graph.render")

local M = {}

local View = {}
View.__index = View

local current_view

local function window_config(width, height, border)
  return {
    relative = "editor",
    width = width,
    height = height,
    row = math.max(0, math.floor((vim.o.lines - height) / 2)),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    style = "minimal",
    border = border,
    title = " Nvaph ",
  }
end

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

function View:setup_window()
  local cfg = config.get().graph.window
  local width = math.max(20, math.floor(vim.o.columns * (cfg.width or 0.85)))
  local height = math.max(10, math.floor(vim.o.lines * (cfg.height or 0.85)))
  self.buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(self.buf, "nvaph://graph")
  vim.bo[self.buf].bufhidden = "wipe"
  vim.bo[self.buf].swapfile = false
  vim.bo[self.buf].filetype = "nvaph"
  self.previous_win = vim.api.nvim_get_current_win()
  self.win = vim.api.nvim_open_win(self.buf, true, window_config(width, height, cfg.border or "rounded"))
  self.width = width
  self.height = height
  self.namespace = vim.api.nvim_create_namespace("nvaph-graph")
  self.augroup = vim.api.nvim_create_augroup("NvaphGraphResize", { clear = true })
  vim.api.nvim_create_autocmd("VimResized", {
    group = self.augroup,
    callback = function()
      if current_view == self and vim.api.nvim_win_is_valid(self.win) then
        self:resize()
      end
    end,
  })
  self:set_keymaps()
end

function View:set_keymaps()
  local function map(key, callback)
    vim.keymap.set("n", key, callback, { buffer = self.buf, nowait = true, silent = true })
  end
  map("q", function()
    self:close()
  end)
  map("<Esc>", function()
    self:close()
  end)
  map("<CR>", function()
    self:open_selected()
  end)
  map("r", function()
    self:clear_pins()
    self:reset(true)
  end)
  map("F", function()
    self.zoom = 1
    self:fit()
    self:render()
  end)
  map("+", function()
    self.zoom = clamp(self.zoom * 1.15, 0.4, 4)
    self:render()
  end)
  map("=", function()
    self.zoom = clamp(self.zoom * 1.15, 0.4, 4)
    self:render()
  end)
  map("-", function()
    self.zoom = clamp(self.zoom / 1.15, 0.4, 4)
    self:render()
  end)
  map("<Left>", function()
    self:move("left")
  end)
  map("<Down>", function()
    self:move("down")
  end)
  map("<Right>", function()
    self:move("right")
  end)
  map("<Up>", function()
    self:move("up")
  end)
  map("h", function()
    self:move("left")
  end)
  map("j", function()
    self:move("down")
  end)
  map("k", function()
    self:move("up")
  end)
  map("l", function()
    self:move("right")
  end)
  map("<Tab>", function()
    self:cycle(1)
  end)
  map("<S-Tab>", function()
    self:cycle(-1)
  end)
  map("/", function()
    self:search()
  end)
  map("?", function()
    self:help()
  end)
  map("<LeftMouse>", function()
    self:begin_drag()
  end)
  map("<LeftDrag>", function()
    self:drag()
  end)
  map("<LeftRelease>", function()
    self:release_drag()
  end)
end

function View:dimensions()
  local width = math.max(20, self.width - 2)
  local height = math.max(8, self.height - 2)
  return width, height
end

function View:fit()
  if not self.positions then
    return
  end
  local width, height = self:dimensions()
  local merged = {}
  for id, point in pairs(self.positions) do
    merged[id] = { x = point.x, y = point.y }
  end
  for id, point in pairs(self.pinned or {}) do
    merged[id] = { x = point.x, y = point.y }
  end
  self.positions = layout.fit(merged, width * 2, height * 4, 2)
  self.pinned = {}
end

function View:update_positions()
  if not self.layout then
    return
  end
  local positions = self.layout:positions_map()
  local width, height = self:dimensions()
  self.positions = layout.fit(positions, width * 2, height * 4, 2)
end

function View:reset(animate)
  local width, height = self:dimensions()
  self.zoom = 1
  self.pinned = {}
  self.layout = layout.new(self.model, width * 2, height * 4, config.get().graph)
  self:stop_timer()
  if animate and config.get().graph.animate then
    self:update_positions()
    self:start_timer()
  else
    self.layout:run()
    self:update_positions()
  end
  self:render()
end

function View:start_timer()
  self:stop_timer()
  local interval = math.max(16, math.floor(1000 / math.max(1, config.get().graph.fps or 30)))
  self.timer = vim.uv.new_timer()
  self.timer:start(interval, interval, vim.schedule_wrap(function()
    if not self.layout or self.layout:finished() then
      self:stop_timer()
      return
    end
    self.layout:step(6)
    self:update_positions()
    self:render()
  end))
end

function View:stop_timer()
  if self.timer then
    self.timer:stop()
    if not self.timer:is_closing() then
      self.timer:close()
    end
    self.timer = nil
  end
end

function View:render_positions()
  if not self.positions then
    return {}
  end
  local out = {}
  for id, point in pairs(self.positions) do
    out[id] = { x = point.x, y = point.y }
  end
  for id, point in pairs(self.pinned or {}) do
    out[id] = { x = point.x, y = point.y }
  end
  if self.zoom == 1 then
    return out
  end
  local width, height = self:dimensions()
  local center_x = width
  local center_y = height * 2
  for id, point in pairs(out) do
    out[id] = {
      x = center_x + (point.x - center_x) * self.zoom,
      y = center_y + (point.y - center_y) * self.zoom,
    }
  end
  return out
end

function View:render()
  if not self.positions or not vim.api.nvim_win_is_valid(self.win) then
    return
  end
  local width, height = self:dimensions()
  self.frame = render.build(self.model, self:render_positions(), width, height, {
    label_count = config.get().graph.label_count,
    label_max = config.get().graph.label_max,
    focus_id = self.focus_id,
  })
  vim.bo[self.buf].modifiable = true
  vim.api.nvim_buf_set_lines(self.buf, 0, -1, false, self.frame.lines)
  vim.bo[self.buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(self.buf, self.namespace, 0, -1)
  for _, span in ipairs(self.frame.spans) do
    pcall(vim.api.nvim_buf_set_extmark, self.buf, self.namespace, span.row, span.byte_start, {
      end_col = span.byte_end,
      hl_group = span.highlight,
    })
  end
  if self.focus_id and self.frame.node_cursor[self.focus_id] then
    local cursor = self.frame.node_cursor[self.focus_id]
    pcall(vim.api.nvim_win_set_cursor, self.win, { cursor.row + 1, cursor.byte })
  end
end

function View:set_focus(id)
  if not id or not self.model.node_map[id] then
    return
  end
  self.focus_id = id
  self:render()
end

function View:base_to_screen(x, y)
  local width, height = self:dimensions()
  if self.zoom == 1 then
    return { x = x, y = y }
  end
  return {
    x = width + (x - width) * self.zoom,
    y = height * 2 + (y - height * 2) * self.zoom,
  }
end

function View:screen_to_base(x, y)
  local width, height = self:dimensions()
  if self.zoom == 1 then
    return { x = x, y = y }
  end
  return {
    x = width + (x - width) / self.zoom,
    y = height * 2 + (y - height * 2) / self.zoom,
  }
end

function View:mouse_position()
  local position = vim.fn.getmousepos()
  if type(position) ~= "table" or position.winid == 0 or position.winid ~= self.win then
    return nil
  end
  return position
end

function View:mouse_cell()
  local position = self:mouse_position()
  if not position then
    return nil, nil
  end
  return position.winrow, position.wincol
end

function View:begin_drag()
  if not self.frame then
    return
  end
  local position = self:mouse_position()
  if not position then
    return
  end
  local row, col = position.winrow, position.wincol
  local id = render.hit(self.frame, position.line - 1, position.column - 1)
  local cell = id and self.frame.node_cell[id]
  local base = id and self.positions[id]
  if not id or not cell or not base or not row or not col then
    return
  end
  self:set_focus(id)
  self.drag_id = id
  self.drag_grab = { row = row, col = col }
  self.drag_origin = self:base_to_screen(base.x, base.y)
  self.pinned[id] = { x = base.x, y = base.y }
  self:stop_timer()
end

function View:drag()
  if not self.drag_id or not self.drag_grab then
    return
  end
  local row, col = self:mouse_cell()
  if not row or not col then
    return
  end
  local width, height = self:dimensions()
  local point = self:screen_to_base(
    self.drag_origin.x + (col - self.drag_grab.col) * 2,
    self.drag_origin.y + (row - self.drag_grab.row) * 4
  )
  point.x = clamp(point.x, 0, width * 2)
  point.y = clamp(point.y, 0, height * 4)
  self.pinned[self.drag_id] = point
  self:render()
end

function View:release_drag()
  self.drag_id = nil
  self.drag_grab = nil
  self.drag_origin = nil
end

function View:clear_pins()
  self.pinned = {}
  self.drag_id = nil
  self.drag_grab = nil
  self.drag_origin = nil
end

function View:node_under_cursor()
  if not self.frame then
    return nil
  end
  local cursor = vim.api.nvim_win_get_cursor(self.win)
  return render.hit(self.frame, cursor[1] - 1, cursor[2]) or self.focus_id
end

function View:move(direction)
  local current = self:node_under_cursor() or self.focus_id
  if not current or not self.positions[current] then
    local first = self.model.nodes[1]
    if first then
      self:set_focus(first.id)
    end
    return
  end
  local point = self.positions[current]
  local best
  local best_distance = math.huge
  for _, node in ipairs(self.model.nodes) do
    local candidate = self.positions[node.id]
    if candidate and node.id ~= current then
      local dx = candidate.x - point.x
      local dy = candidate.y - point.y
      local valid = (direction == "left" and dx < 0)
        or (direction == "right" and dx > 0)
        or (direction == "up" and dy < 0)
        or (direction == "down" and dy > 0)
      if valid then
        local distance = dx * dx + dy * dy
        if distance < best_distance then
          best_distance = distance
          best = node
        end
      end
    end
  end
  if best then
    self:set_focus(best.id)
  end
end

function View:cycle(direction)
  if #self.model.nodes == 0 then
    return
  end
  local ids = {}
  for _, node in ipairs(self.model.nodes) do
    ids[#ids + 1] = node.id
  end
  table.sort(ids)
  local index = 1
  for position, id in ipairs(ids) do
    if id == self.focus_id then
      index = position
      break
    end
  end
  index = (index - 1 + direction) % #ids + 1
  self:set_focus(ids[index])
end

function View:open_selected()
  local id = self:node_under_cursor() or self.focus_id
  local node = id and self.model.node_map[id]
  if not node or not node.path or not node.file then
    return
  end
  vim.cmd("edit " .. vim.fn.fnameescape(node.file.abs))
  self:close()
end

function View:search()
  vim.ui.input({ prompt = "Search files: " }, function(query)
    if not query or query == "" then
      return
    end
    local lowered = query:lower()
    for _, node in ipairs(self.model.nodes) do
      local title = node.title:lower()
      local path = (node.path or ""):lower()
      if title:find(lowered, 1, true) or path:find(lowered, 1, true) then
        self:set_focus(node.id)
        return
      end
    end
    util.notify("no matching file")
  end)
end

function View:help()
  util.notify("q close  CR open  hjkl move  r relayout  F fit  +/- zoom  / search  Tab cycle")
end

function View:resize()
  if not vim.api.nvim_win_is_valid(self.win) then
    return
  end
  local cfg = config.get().graph.window
  local width = math.max(20, math.floor(vim.o.columns * (cfg.width or 0.85)))
  local height = math.max(10, math.floor(vim.o.lines * (cfg.height or 0.85)))
  self.width = width
  self.height = height
  vim.api.nvim_win_set_config(self.win, window_config(width, height, cfg.border or "rounded"))
  self:reset(false)
end

function View:close()
  self:stop_timer()
  if self.augroup then
    pcall(vim.api.nvim_del_augroup_by_id, self.augroup)
    self.augroup = nil
  end
  if self.win and vim.api.nvim_win_is_valid(self.win) then
    pcall(vim.api.nvim_win_close, self.win, true)
  end
  if self.previous_win and vim.api.nvim_win_is_valid(self.previous_win) and config.get().ui.return_to_previous then
    pcall(vim.api.nvim_set_current_win, self.previous_win)
  end
  if current_view == self then
    current_view = nil
  end
end

function M.open(data, model, opts)
  if current_view then
    current_view:close()
  end
  render.define_highlights()
  local view = setmetatable({
    data = data,
    model = model,
    opts = opts or {},
    focus_id = model.nodes[1] and model.nodes[1].id,
    zoom = 1,
    pinned = {},
    drag_id = nil,
    drag_grab = nil,
    drag_origin = nil,
  }, View)
  view:setup_window()
  current_view = view
  view:reset(false)
  return view
end

function M.close()
  if current_view then
    current_view:close()
  end
end

return M
