local config = require("nvaph.config")
local index = require("nvaph.index")
local model_builder = require("nvaph.graph.model")
local util = require("nvaph.util")

local M = {}

local function options(opts)
  return vim.tbl_deep_extend("force", vim.deepcopy(config.get()), opts or {})
end

local function index_options(opts)
  return {
    max_files = opts.max_files,
    shallow = config.shallow(opts),
    extensions = opts.extensions,
    ignore = opts.ignore,
    cache = opts.cache.enabled ~= false,
    include_markdown = opts.links.include_markdown,
    include_embeds = opts.links.include_embeds,
    scan_all_files = opts.links.scan_all_files,
    link_extensions = opts.links.link_extensions,
    case_sensitive = opts.links.case_sensitive,
  }
end

local function empty_data()
  return {
    root = "",
    by_path = {},
    lookup = {},
    incoming = {},
    outgoing = {},
    files = {},
    edges = {},
    unresolved = {},
  }
end

local function buffer_state(root)
  local bufnr = vim.api.nvim_get_current_buf()
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == "" or not root or not util.is_within(name, root) then
    return nil, nil
  end
  if not vim.bo[bufnr].modified then
    return nil, nil
  end
  return util.normalize(name), table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
end

function M.data(opts)
  opts = options(opts)
  local root = config.root(opts)
  if not root then
    return empty_data()
  end
  local build_opts = index_options(opts)
  local buffer_path, buffer_text = buffer_state(root)
  if buffer_path then
    build_opts.buffer_path = buffer_path
    build_opts.buffer_text = buffer_text
  end
  return index.build(root, build_opts)
end

function M.graph(opts)
  opts = options(opts)
  local data = M.data(opts)
  if data.root == "" then
    util.notify("no project root detected; open a project file")
    return
  end
  if #data.edges == 0 then
    util.notify("no resolved wikilinks found")
  end
  local graph_opts = vim.deepcopy(opts.graph)
  graph_opts.orphans = graph_opts.show_orphans
  local model = model_builder.build(data, graph_opts)
  return require("nvaph.graph.view").open(data, model, { root = data.root })
end

return M
