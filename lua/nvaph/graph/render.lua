local util = require("nvaph.util")

local M = {}

local Canvas = {}
Canvas.__index = Canvas

local BIT = {
  [0] = { [0] = 0x01, [1] = 0x02, [2] = 0x04, [3] = 0x40 },
  [1] = { [0] = 0x08, [1] = 0x10, [2] = 0x20, [3] = 0x80 },
}

local function index_of(cols, col, row)
  return row * cols + col
end

local function utf8_encode(codepoint)
  if codepoint < 0x80 then
    return string.char(codepoint)
  end
  if codepoint < 0x800 then
    return string.char(0xC0 + math.floor(codepoint / 64), 0x80 + codepoint % 64)
  end
  return string.char(
    0xE0 + math.floor(codepoint / 4096),
    0x80 + math.floor(codepoint / 64) % 64,
    0x80 + codepoint % 64
  )
end

local function utf8_chars(value)
  local chars = {}
  local count = vim.fn.strchars(value)
  for index = 0, count - 1 do
    chars[#chars + 1] = vim.fn.strcharpart(value, index, 1)
  end
  return chars
end

function Canvas.new(cols, rows)
  return setmetatable({
    cols = cols,
    rows = rows,
    masks = {},
    text = {},
    owners = {},
    highlights = {},
  }, Canvas)
end

function Canvas:set_dot(x, y, highlight, owner, kind)
  x = math.floor(x + 0.5)
  y = math.floor(y + 0.5)
  if x < 0 or y < 0 or x >= self.cols * 2 or y >= self.rows * 4 then
    return
  end
  local col = math.floor(x / 2)
  local row = math.floor(y / 4)
  local index = index_of(self.cols, col, row)
  self.masks[index] = (self.masks[index] or 0) | BIT[x % 2][y % 4]
  if not self.owners[index] then
    self.owners[index] = owner
    self.highlights[index] = highlight
  end
end

function Canvas:line(x1, y1, x2, y2, highlight, owner)
  x1 = math.floor(x1 + 0.5)
  y1 = math.floor(y1 + 0.5)
  x2 = math.floor(x2 + 0.5)
  y2 = math.floor(y2 + 0.5)
  local dx = math.abs(x2 - x1)
  local dy = -math.abs(y2 - y1)
  local sx = x1 < x2 and 1 or -1
  local sy = y1 < y2 and 1 or -1
  local error = dx + dy
  while true do
    self:set_dot(x1, y1, highlight, owner, "edge")
    if x1 == x2 and y1 == y2 then
      break
    end
    local doubled = 2 * error
    if doubled >= dy then
      error = error + dy
      x1 = x1 + sx
    end
    if doubled <= dx then
      error = error + dx
      y1 = y1 + sy
    end
  end
end

function Canvas:text_free(col, row, length)
  if col < 0 or row < 0 or row >= self.rows or col + length > self.cols then
    return false
  end
  for offset = 0, length - 1 do
    if self.text[index_of(self.cols, col + offset, row)] then
      return false
    end
  end
  return true
end

function Canvas:set_text(col, row, value, highlight, owner, kind)
  if row < 0 or row >= self.rows then
    return
  end
  local chars = utf8_chars(value)
  for offset, char in ipairs(chars) do
    local cell = col + offset - 1
    if cell >= 0 and cell < self.cols then
      local index = index_of(self.cols, cell, row)
      self.text[index] = char
      self.owners[index] = owner
      self.highlights[index] = highlight
    end
  end
end

function Canvas:to_lines()
  local lines = {}
  local spans = {}
  for row = 0, self.rows - 1 do
    local parts = {}
    local byte_position = 0
    local open
    for col = 0, self.cols - 1 do
      local index = index_of(self.cols, col, row)
      local char = self.text[index]
      if not char and self.masks[index] then
        char = utf8_encode(0x2800 + self.masks[index])
      end
      char = char or " "
      parts[#parts + 1] = char
      local highlight = self.highlights[index]
      local owner = self.owners[index]
      if char == " " then
        highlight = nil
        owner = nil
      end
      local byte_width = #char
      if open and open.highlight == highlight and open.owner == owner then
        open.byte_end = byte_position + byte_width
      else
        if open then
          spans[#spans + 1] = open
        end
        open = highlight and {
          row = row,
          byte_start = byte_position,
          byte_end = byte_position + byte_width,
          highlight = highlight,
          owner = owner,
        } or nil
      end
      byte_position = byte_position + byte_width
    end
    if open then
      spans[#spans + 1] = open
    end
    lines[#lines + 1] = table.concat(parts)
  end
  return lines, spans
end

function M.define_highlights()
  local groups = {
    NvaphNode = { link = "Function" },
    NvaphGhost = { link = "Comment" },
    NvaphLabel = { link = "Normal" },
    NvaphEdge = { link = "NonText" },
    NvaphEdgeFocus = { link = "Function" },
    NvaphFocus = { link = "IncSearch" },
    NvaphDim = { link = "NonText" },
  }
  for name, value in pairs(groups) do
    vim.api.nvim_set_hl(0, name, vim.tbl_extend("force", value, { default = true }))
  end
end

local function node_glyph(node)
  if node.kind == "ghost" then
    return "○"
  end
  return "●"
end

local function truncate(value, limit)
  if util.display_width(value) <= limit then
    return value
  end
  local result = ""
  for index = 0, vim.fn.strchars(value) - 1 do
    local char = vim.fn.strcharpart(value, index, 1)
    if util.display_width(result .. char) > limit - 1 then
      return result .. "…"
    end
    result = result .. char
  end
  return result
end

function M.node_cell(point, cols, rows)
  return {
    col = math.max(0, math.min(cols - 1, math.floor(point.x / 2))),
    row = math.max(0, math.min(rows - 1, math.floor(point.y / 4))),
  }
end

function M.build(model, positions, cols, rows, opts)
  opts = opts or {}
  local canvas = Canvas.new(cols, rows)
  local focus_id = opts.focus_id
  local node_cell = {}
  local anchor = {}
  for _, node in ipairs(model.nodes) do
    local point = positions[node.id]
    if point then
      local cell = M.node_cell(point, cols, rows)
      node_cell[node.id] = cell
      anchor[node.id] = { x = cell.col * 2 + 1, y = cell.row * 4 + 2 }
    end
  end
  for _, edge in ipairs(model.edges) do
    local source = anchor[edge.source] or positions[edge.source]
    local target = anchor[edge.target] or positions[edge.target]
    if source and target then
      local highlight = focus_id and (edge.source == focus_id or edge.target == focus_id) and "NvaphEdgeFocus" or "NvaphEdge"
      canvas:line(source.x, source.y, target.x, target.y, highlight, edge.source .. ">" .. edge.target)
    end
  end
  local nodes = {}
  for _, node in ipairs(model.nodes) do
    nodes[#nodes + 1] = node
  end
  table.sort(nodes, function(left, right)
    local left_degree = left.in_degree + left.out_degree
    local right_degree = right.in_degree + right.out_degree
    if left_degree == right_degree then
      return left.id < right.id
    end
    return left_degree > right_degree
  end)
  for _, node in ipairs(nodes) do
    local cell = node_cell[node.id]
    if cell then
      local highlight = node.kind == "ghost" and "NvaphGhost" or "NvaphNode"
      if focus_id and node.id == focus_id then
        highlight = "NvaphFocus"
      end
      canvas:set_text(cell.col, cell.row, node_glyph(node), highlight, node.id, "node")
    end
  end
  local label_count = opts.label_count or math.min(#nodes, 80)
  local labeled = 0
  for _, node in ipairs(nodes) do
    if labeled < label_count then
      local cell = node_cell[node.id]
      local point = positions[node.id]
      if cell and point then
        local label = truncate(node.title, opts.label_max or 28)
        local length = util.display_width(label)
        local candidates = {
          { cell.col + 2, cell.row },
          { cell.col - length - 1, cell.row },
          { cell.col - math.floor(length / 2), cell.row + 1 },
          { cell.col - math.floor(length / 2), cell.row - 1 },
        }
        for _, candidate in ipairs(candidates) do
          if canvas:text_free(candidate[1] - 1, candidate[2], length + 2) then
            local highlight = node.id == focus_id and "NvaphFocus" or "NvaphLabel"
            canvas:set_text(candidate[1], candidate[2], label, highlight, node.id, "label")
            labeled = labeled + 1
            break
          end
        end
      end
    end
  end
  local lines, spans = canvas:to_lines()
  local hitmap = {}
  local node_cursor = {}
  for _, span in ipairs(spans) do
    if span.owner and model.node_map[span.owner] then
      hitmap[span.row] = hitmap[span.row] or {}
      table.insert(hitmap[span.row], {
        byte_start = span.byte_start,
        byte_end = span.byte_end,
        id = span.owner,
      })
      if span.highlight and node_cursor[span.owner] == nil and node_cell[span.owner] then
        node_cursor[span.owner] = { row = node_cell[span.owner].row, byte = span.byte_start }
      end
    end
  end
  for _, row_hits in pairs(hitmap) do
    table.sort(row_hits, function(left, right)
      return left.byte_start < right.byte_start
    end)
  end
  for id, cell in pairs(node_cell) do
    if not node_cursor[id] then
      node_cursor[id] = { row = cell.row, byte = cell.col }
    end
  end
  return {
    lines = lines,
    spans = spans,
    hitmap = hitmap,
    node_cursor = node_cursor,
    node_cell = node_cell,
    cols = cols,
    rows = rows,
  }
end

function M.hit_cell(frame, row, col)
  for id, cell in pairs(frame.node_cell or {}) do
    if cell.row == row and cell.col == col then
      return id
    end
  end
  return nil
end

function M.hit(frame, row, byte_column)
  local hits = frame.hitmap[row]
  if not hits then
    return nil
  end
  for _, hit in ipairs(hits) do
    if byte_column >= hit.byte_start and byte_column < hit.byte_end then
      return hit.id
    end
  end
  return nil
end

return M
