local util = require("nvaph.util")
local workspace = require("nvaph.workspace")
local cache = require("nvaph.cache")
local parser = require("nvaph.links.parser")
local frontmatter = require("nvaph.links.frontmatter")
local resolver = require("nvaph.links.resolve")

local M = {}
M.version = 3

local function markdown_file(file)
  return file.extension == ".md" or file.extension == ".mdx" or file.extension == ".markdown"
end

local default_link_extensions = { ".md", ".mdx", ".markdown", ".txt", ".org", ".rst", ".adoc", ".tex", ".typ" }

local function link_source(file, opts)
  if opts.scan_all_files == true then
    return file.size <= 1024 * 1024
  end
  for _, extension in ipairs(opts.link_extensions or default_link_extensions) do
    if file.extension == extension:lower() then
      return true
    end
  end
  return false
end

local function first_heading(lines, start)
  for index = start, #lines do
    local heading = lines[index]:match("^#%s+(.+)$")
    if heading then
      return util.trim(heading)
    end
  end
  return nil
end

local function title_for(file, text, meta)
  if not markdown_file(file) then
    return file.rel
  end
  if type(meta.title) == "string" and util.trim(meta.title) ~= "" then
    return util.trim(meta.title)
  end
  local lines = vim.split(text or "", "\n", { plain = true })
  return first_heading(lines, 1) or file.rel:gsub("%.[^.]+$", "")
end

local function cache_valid(cached, files, root, shallow)
  if not cached or cached.version ~= M.version or cached.root ~= root or cached.shallow ~= shallow then
    return false
  end
  if type(cached.file_meta) ~= "table" then
    return false
  end
  local cached_count = 0
  for _ in pairs(cached.file_meta) do
    cached_count = cached_count + 1
  end
  if cached_count ~= #files then
    return false
  end
  for _, file in ipairs(files) do
    local saved = cached.file_meta[file.rel]
    if not saved or saved.mtime ~= file.mtime or saved.size ~= file.size then
      return false
    end
  end
  return true
end

local function add_edge(map, list, source, target, kind, link)
  local key = table.concat({ source, target, kind }, "\0")
  local edge = map[key]
  if not edge then
    edge = { source = source, target = target, kind = kind, count = 0, links = {} }
    map[key] = edge
    list[#list + 1] = edge
  end
  edge.count = edge.count + 1
  edge.links[#edge.links + 1] = {
    row = link.row,
    start_col = link.start_col,
    end_col = link.end_col,
    raw = link.raw,
  }
end

local function decorate(data, opts)
  data.by_path = {}
  for _, file in ipairs(data.files) do
    data.by_path[file.path] = file
  end
  data.lookup = resolver.build_lookup(data.files, opts)
  data.incoming = {}
  data.outgoing = {}
  for _, edge in ipairs(data.edges) do
    data.outgoing[edge.source] = data.outgoing[edge.source] or {}
    data.incoming[edge.target] = data.incoming[edge.target] or {}
    table.insert(data.outgoing[edge.source], edge)
    table.insert(data.incoming[edge.target], edge)
  end
  for _, file in ipairs(data.files) do
    file.in_degree = #(data.incoming[file.path] or {})
    file.out_degree = #(data.outgoing[file.path] or {})
  end
  return data
end

function M.build(root, opts)
  opts = opts or {}
  root = util.normalize(root)
  local files = workspace.scan(root, opts)
  local buffer_path = opts.buffer_path and util.normalize(opts.buffer_path) or nil
  local buffer_rel = buffer_path and util.relative(buffer_path, root) or nil
  local buffer_text = opts.buffer_text
  if buffer_rel and buffer_text ~= nil then
    local found = false
    for _, file in ipairs(files) do
      if file.rel == buffer_rel then
        found = true
        break
      end
    end
    if not found then
      local stat = vim.uv.fs_stat(buffer_path) or {}
      files[#files + 1] = {
        abs = buffer_path,
        rel = buffer_rel,
        extension = util.extension(buffer_path):lower(),
        mtime = stat.mtime and stat.mtime.sec or 0,
        size = #buffer_text,
      }
    end
  end
  local function content_for(file)
    if buffer_rel and file.rel == buffer_rel and buffer_text ~= nil then
      return buffer_text
    end
    return util.read(file.abs) or ""
  end
  local cached = opts.cache == false and nil or cache.load(root)
  if buffer_text == nil and cache_valid(cached, files, root, opts.shallow == true) then
    return decorate(cached, opts)
  end
  local file_records = {}
  for _, file in ipairs(files) do
    local source = link_source(file, opts)
    local text = source and content_for(file) or ""
    local parsed = markdown_file(file) and source and frontmatter.parse(text) or { meta = {} }
    local record = {
      path = file.rel,
      abs = file.abs,
      stem = util.stem(file.rel),
      extension = file.extension,
      kind = "file",
      text = file.text,
      title = "",
      aliases = frontmatter.list(parsed.meta.aliases),
      tags = frontmatter.tags(parsed.meta.tags),
      mtime = file.mtime,
      size = file.size,
    }
    record.title = title_for(file, text, parsed.meta)
    file_records[#file_records + 1] = record
  end
  local lookup = resolver.build_lookup(file_records, opts)
  local edges = {}
  local edge_map = {}
  local unresolved = {}
  local unresolved_map = {}
  for _, file in ipairs(files) do
    if link_source(file, opts) then
      local text = content_for(file)
      for _, link in ipairs(parser.parse(text)) do
        if (link.kind ~= "markdown" or opts.include_markdown ~= false)
          and (link.kind ~= "embed" or opts.include_embeds ~= false) then
          local result = resolver.resolve(link, { path = file.rel, title = util.stem(file.rel) }, lookup, opts)
          if result.status == "resolved" then
            add_edge(edge_map, edges, file.rel, result.file.path, link.kind, link)
          elseif result.status == "unresolved" then
            local target = result.target
            local key = table.concat({ file.rel, target, link.kind }, "\0")
            local item = unresolved_map[key]
            if not item then
              item = { source = file.rel, target = target, kind = link.kind, count = 0, links = {} }
              unresolved_map[key] = item
              unresolved[#unresolved + 1] = item
            end
            item.count = item.count + 1
            item.links[#item.links + 1] = {
              row = link.row,
              start_col = link.start_col,
              end_col = link.end_col,
              raw = link.raw,
            }
          end
        end
      end
    end
  end
  local data = {
    version = M.version,
    root = root,
    shallow = opts.shallow == true,
    file_meta = {},
    files = file_records,
    edges = edges,
    unresolved = unresolved,
  }
  for _, file in ipairs(files) do
    data.file_meta[file.rel] = { mtime = file.mtime, size = file.size }
  end
  if opts.cache ~= false and buffer_text == nil then
    cache.save(root, data)
  end
  return decorate(data, opts)
end

function M.ghost_id(target)
  return "\0ghost:" .. util.normalize(target):lower()
end

function M.invalidate(root)
  cache.clear(util.normalize(root))
end

return M
