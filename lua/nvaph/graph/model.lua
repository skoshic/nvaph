local M = {}

function M.add(map, list, key, value)
  if not map[key] then
    map[key] = {}
    list[#list + 1] = key
  end
  table.insert(map[key], value)
end

function M.node(id, file, kind)
  local title = file and file.title or id:gsub("^%z", "")
  return {
    id = id,
    path = file and file.path or nil,
    file = file,
    kind = kind or "file",
    title = title,
    tags = file and file.tags or {},
    in_degree = file and file.in_degree or 0,
    out_degree = file and file.out_degree or 0,
  }
end

local function edge_enabled(edge, opts)
  return edge.kind ~= "function" or opts.show_function_edges == true
end

function M.build(data, opts)
  opts = opts or {}
  local model = {
    nodes = {},
    node_map = {},
    edges = {},
    adjacency = {},
    incoming = {},
    outgoing = {},
  }
  local function add_node(node)
    if model.node_map[node.id] then
      return
    end
    model.node_map[node.id] = node
    model.nodes[#model.nodes + 1] = node
  end
  for _, file in ipairs(data.files) do
    add_node(M.node(file.path, file))
  end
  for _, item in ipairs(data.unresolved) do
    if opts.show_unresolved ~= false then
      add_node(M.node(require("nvaph.index").ghost_id(item.target), nil, "ghost"))
    end
  end
  for _, edge in ipairs(data.edges) do
    local source = model.node_map[edge.source]
    local target = model.node_map[edge.target]
    if edge_enabled(edge, opts) and source and target then
      local item = {
        source = source.id,
        target = target.id,
        kind = edge.kind,
        count = edge.count,
        links = edge.links,
      }
      model.edges[#model.edges + 1] = item
      M.add(model.adjacency, {}, source.id, target.id)
      M.add(model.adjacency, {}, target.id, source.id)
      M.add(model.outgoing, {}, source.id, item)
      M.add(model.incoming, {}, target.id, item)
      source.out_degree = source.out_degree + edge.count
      target.in_degree = target.in_degree + edge.count
    end
  end
  for _, item in ipairs(data.unresolved) do
    if opts.show_unresolved ~= false then
      local target = model.node_map[require("nvaph.index").ghost_id(item.target)]
      local source = model.node_map[item.source]
      if edge_enabled(item, opts) and target and source then
        local edge = {
          source = source.id,
          target = target.id,
          kind = item.kind,
          count = item.count,
          links = item.links,
        }
        model.edges[#model.edges + 1] = edge
        M.add(model.adjacency, {}, source.id, target.id)
        M.add(model.adjacency, {}, target.id, source.id)
        M.add(model.outgoing, {}, source.id, edge)
        M.add(model.incoming, {}, target.id, edge)
      end
    end
  end
  if opts.linked_only ~= false then
    local keep = {}
    for _, edge in ipairs(model.edges) do
      keep[edge.source] = true
      keep[edge.target] = true
    end
    local nodes = {}
    for _, node in ipairs(model.nodes) do
      if keep[node.id] then
        nodes[#nodes + 1] = node
      end
    end
    model.nodes = nodes
  end
  if opts.max_nodes and #model.nodes > opts.max_nodes then
    table.sort(model.nodes, function(left, right)
      if left.in_degree + left.out_degree == right.in_degree + right.out_degree then
        return left.id < right.id
      end
      return left.in_degree + left.out_degree > right.in_degree + right.out_degree
    end)
    local keep = {}
    for index = 1, opts.max_nodes do
      keep[model.nodes[index].id] = true
    end
    local nodes = {}
    for _, node in ipairs(model.nodes) do
      if keep[node.id] then
        nodes[#nodes + 1] = node
      end
    end
    model.nodes = nodes
    local edges = {}
    for _, edge in ipairs(model.edges) do
      if keep[edge.source] and keep[edge.target] then
        edges[#edges + 1] = edge
      end
    end
    model.edges = edges
  end
  if opts.orphans == false then
    local keep = {}
    for _, node in ipairs(model.nodes) do
      if node.in_degree + node.out_degree > 0 then
        keep[node.id] = true
      end
    end
    local nodes = {}
    for _, node in ipairs(model.nodes) do
      if keep[node.id] then
        nodes[#nodes + 1] = node
      end
    end
    model.nodes = nodes
  end
  return model
end

return M
