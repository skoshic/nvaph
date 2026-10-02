local util = require("nvaph.util")

local M = {}
M.__index = M

local Layout = {}
Layout.__index = Layout

function M.new(model, width, height, opts)
  local self = setmetatable({
    model = model,
    width = math.max(1, width),
    height = math.max(1, height),
    opts = opts or {},
    positions = {},
    displacement = {},
    ids = {},
    edges = {},
    iteration = 0,
    temperature = 1,
  }, Layout)
  local ids = {}
  for _, node in ipairs(model.nodes) do
    ids[#ids + 1] = node.id
  end
  table.sort(ids)
  self.ids = ids
  for _, edge in ipairs(model.edges) do
    self.edges[#self.edges + 1] = edge
  end
  table.sort(self.edges, function(left, right)
    return (left.source .. left.target) < (right.source .. right.target)
  end)
  local count = math.max(#ids, 1)
  self.k = math.min((self.opts.edge_length or 16) * 2, math.sqrt((self.width * self.height) / count) * 0.7)
  self.max_iterations = self.opts.iterations or 240
  self.temperature = math.min(self.width, self.height) / 8
  self.floor_temperature = 0.4
  self.cooling = (self.floor_temperature / math.max(self.temperature, 0.0001)) ^ (1 / self.max_iterations)
  for index, id in ipairs(ids) do
    self.positions[id] = {
      x = self.width * (0.1 + 0.8 * util.hash01(id .. ":x")),
      y = self.height * (0.1 + 0.8 * util.hash01(id .. ":y")),
    }
    self.displacement[id] = { x = 0, y = 0 }
  end
  return self
end

function Layout:step(count)
  count = count or 1
  if #self.ids == 0 then
    return true
  end
  for _ = 1, count do
    if self.iteration >= self.max_iterations then
      return true
    end
    self.iteration = self.iteration + 1
    local grid = {}
    local cell = math.max(self.k * 3, 1)
    for _, id in ipairs(self.ids) do
      local point = self.positions[id]
      local key = math.floor(point.x / cell) .. ":" .. math.floor(point.y / cell)
      grid[key] = grid[key] or {}
      table.insert(grid[key], id)
    end
    for _, id in ipairs(self.ids) do
      local point = self.positions[id]
      local gx = math.floor(point.x / cell)
      local gy = math.floor(point.y / cell)
      local force = self.displacement[id]
      force.x = 0
      force.y = 0
      for ox = -1, 1 do
        for oy = -1, 1 do
          local bucket = grid[(gx + ox) .. ":" .. (gy + oy)]
          if bucket then
            for _, other in ipairs(bucket) do
              if other ~= id then
                local other_point = self.positions[other]
                local dx = point.x - other_point.x
                local dy = point.y - other_point.y
                local distance_squared = dx * dx + dy * dy
                if distance_squared < 0.01 then
                  dx = util.hash01(id .. other .. ":dx") - 0.5
                  dy = util.hash01(id .. other .. ":dy") - 0.5
                  distance_squared = dx * dx + dy * dy + 0.0001
                end
                if distance_squared < cell * cell then
                  local distance = math.sqrt(distance_squared)
                  local magnitude = (self.opts.repulsion or 1) * self.k * self.k / distance
                  force.x = force.x + dx / distance * magnitude
                  force.y = force.y + dy / distance * magnitude
                end
              end
            end
          end
        end
      end
    end
    for _, edge in ipairs(self.edges) do
      local source = self.positions[edge.source]
      local target = self.positions[edge.target]
      if source and target then
        local dx = source.x - target.x
        local dy = source.y - target.y
        local distance = math.sqrt(dx * dx + dy * dy)
        if distance > 0.01 then
          local magnitude = (self.opts.spring or 1) * distance * distance / self.k / distance
          local x = dx * magnitude
          local y = dy * magnitude
          self.displacement[edge.source].x = self.displacement[edge.source].x - x
          self.displacement[edge.source].y = self.displacement[edge.source].y - y
          self.displacement[edge.target].x = self.displacement[edge.target].x + x
          self.displacement[edge.target].y = self.displacement[edge.target].y + y
        end
      end
    end
    local center_x = self.width / 2
    local center_y = self.height / 2
    local gravity = self.opts.gravity or 0.06
    for _, id in ipairs(self.ids) do
      local point = self.positions[id]
      local force = self.displacement[id]
      force.x = force.x + (center_x - point.x) * gravity
      force.y = force.y + (center_y - point.y) * gravity
    end
    for _, id in ipairs(self.ids) do
      local point = self.positions[id]
      local force = self.displacement[id]
      local distance = math.sqrt(force.x * force.x + force.y * force.y)
      if distance > 0.01 then
        local scale = math.min(distance, self.temperature) / distance
        point.x = point.x + force.x * scale
        point.y = point.y + force.y * scale
      end
      point.x = math.max(1, math.min(self.width - 1, point.x))
      point.y = math.max(1, math.min(self.height - 1, point.y))
    end
    self.temperature = math.max(self.floor_temperature, self.temperature * self.cooling)
  end
  return self.iteration >= self.max_iterations
end

function Layout:run()
  while not self:step(25) do
  end
  return self.positions
end

function Layout:finished()
  return self.iteration >= self.max_iterations
end

function Layout:positions_map()
  return self.positions
end

function M.fit(positions, width, height, padding)
  padding = padding or 2
  if not positions then
    return {}
  end
  local min_x, min_y = math.huge, math.huge
  local max_x, max_y = -math.huge, -math.huge
  for _, point in pairs(positions) do
    min_x = math.min(min_x, point.x)
    min_y = math.min(min_y, point.y)
    max_x = math.max(max_x, point.x)
    max_y = math.max(max_y, point.y)
  end
  if min_x == math.huge then
    return {}
  end
  local source_width = math.max(max_x - min_x, 1)
  local source_height = math.max(max_y - min_y, 1)
  local target_width = math.max(width - padding * 2, 1)
  local target_height = math.max(height - padding * 2, 1)
  local scale = math.min(1, target_width / source_width, target_height / source_height)
  local out = {}
  for id, point in pairs(positions) do
    out[id] = {
      x = padding + (point.x - min_x) * scale + (target_width - source_width * scale) / 2,
      y = padding + (point.y - min_y) * scale + (target_height - source_height * scale) / 2,
    }
  end
  return out
end

return M
