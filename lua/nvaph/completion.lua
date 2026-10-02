local config = require("nvaph.config")
local index = require("nvaph.index")

local M = {}

local function score(file, query)
  if query == "" then
    return 0
  end
  local title = file.title:lower()
  local path = file.path:lower()
  local alias_text = table.concat(file.aliases or {}, " "):lower()
  if title == query then
    return 0
  end
  if title:sub(1, #query) == query then
    return 1
  end
  if path:sub(1, #query) == query then
    return 2
  end
  if alias_text:find(query, 1, true) then
    return 3
  end
  if title:find(query, 1, true) then
    return 4
  end
  if path:find(query, 1, true) then
    return 5
  end
  return nil
end

function M.candidates(prefix, opts)
  opts = opts or {}
  local query = (prefix or ""):lower()
  local root = config.root(opts)
  if not root then
    return {}
  end
  local cfg = config.get()
  local build_opts = {
    max_files = cfg.max_files,
    shallow = config.shallow(opts),
    extensions = cfg.extensions,
    ignore = cfg.ignore,
    cache = cfg.cache.enabled,
    include_markdown = cfg.links.include_markdown,
    include_embeds = cfg.links.include_embeds,
    scan_all_files = cfg.links.scan_all_files,
    link_extensions = cfg.links.link_extensions,
    case_sensitive = cfg.links.case_sensitive,
  }
  local bufnr = vim.api.nvim_get_current_buf()
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name ~= "" and vim.bo[bufnr].modified and require("nvaph.util").is_within(name, root) then
    build_opts.buffer_path = name
    build_opts.buffer_text = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
  end
  local data = index.build(root, build_opts)
  local items = {}
  for _, file in ipairs(data.files) do
    local value = score(file, query)
    if value then
      items[#items + 1] = {
        score = value,
        label = file.title,
        kind = "Reference",
        detail = file.path,
        documentation = file.path,
        insertText = "[[" .. file.path .. "]]",
        file = file,
      }
    end
  end
  table.sort(items, function(left, right)
    if left.score == right.score then
      return left.label < right.label
    end
    return left.score < right.score
  end)
  return items
end

function M.cmp_source()
  local source = {}
  function source:complete(_, params, callback)
    local line = params.context and params.context.cursor_before_line or ""
    local prefix = line:match("%[%[([^%]]*)$") or ""
    callback({ items = M.candidates(prefix), isIncomplete = false })
  end
  return source
end

return M
