local M = {}

local function clean(value)
  value = value or ""
  value = value:gsub("^%s+", ""):gsub("%s+$", "")
  value = value:gsub("\\", "/")
  value = value:gsub("^%./", "")
  return value
end

local function has_extension(value, extensions)
  for _, extension in ipairs(extensions) do
    if value:sub(-#extension) == extension then
      return true
    end
  end
  return false
end

local function normalize_case(value, case_sensitive)
  if case_sensitive then
    return value
  end
  return value:lower()
end

function M.build_lookup(files, opts)
  opts = opts or {}
  local case_sensitive = opts.case_sensitive == true
  local lookup = {
    path = {},
    relative = {},
    stem = {},
    title = {},
    alias = {},
  }
  local function add(map, key, file)
    if key == nil or key == "" then
      return
    end
    key = normalize_case(clean(tostring(key)), case_sensitive)
    map[key] = map[key] or {}
    table.insert(map[key], file)
  end
  for _, file in ipairs(files) do
    add(lookup.path, file.path, file)
    add(lookup.relative, file.path:gsub("%.[^.]+$", ""), file)
    add(lookup.stem, file.stem, file)
    add(lookup.title, file.title, file)
    for _, alias in ipairs(file.aliases or {}) do
      add(lookup.alias, alias, file)
    end
  end
  return lookup
end

local function unique(files)
  local seen = {}
  local out = {}
  for _, file in ipairs(files) do
    if not seen[file.path] then
      seen[file.path] = true
      out[#out + 1] = file
    end
  end
  return out
end

local function choose(candidates, target, case_sensitive)
  if not candidates or #candidates == 0 then
    return nil
  end
  if #candidates == 1 then
    return candidates[1]
  end
  local exact = {}
  local wanted = normalize_case(target, case_sensitive)
  for _, file in ipairs(candidates) do
    local keys = { file.path, file.stem, file.title }
    for _, alias in ipairs(file.aliases or {}) do
      keys[#keys + 1] = alias
    end
    for _, key in ipairs(keys) do
      if normalize_case(clean(tostring(key)), case_sensitive) == wanted then
        exact[#exact + 1] = file
        break
      end
    end
  end
  if #exact == 1 then
    return exact[1]
  end
  return nil
end

function M.resolve(link, source, lookup, opts)
  opts = opts or {}
  local case_sensitive = opts.case_sensitive == true
  local target = clean(link.target)
  if target == "" then
    return { status = "resolved", file = source }
  end
  if link.external or target:match("^#") then
    return { status = "external" }
  end
  local extensions = {}
  if opts.extension then
    extensions[#extensions + 1] = opts.extension
  elseif type(opts.extensions) == "table" then
    extensions = opts.extensions
  end
  local paths = { target }
  if #extensions > 0 and not has_extension(target, extensions) then
    for _, extension in ipairs(extensions) do
      paths[#paths + 1] = target .. extension
    end
  end
  for _, path in ipairs(paths) do
    local direct = lookup.path[normalize_case(path, case_sensitive)]
    local file = choose(direct, path, case_sensitive)
    if file then
      return { status = "resolved", file = file }
    end
  end
  local relative = lookup.relative[normalize_case(target, case_sensitive)]
  local relative_file = choose(relative, target, case_sensitive)
  if relative_file then
    return { status = "resolved", file = relative_file }
  end
  local basename = vim.fs.basename(target)
  local stem = basename:gsub("%.[^.]+$", "")
  local candidates = {}
  for _, map in ipairs({ lookup.stem, lookup.title, lookup.alias }) do
    local found = map[normalize_case(stem, case_sensitive)]
    if found then
      for _, file in ipairs(found) do
        candidates[#candidates + 1] = file
      end
    end
  end
  local file = choose(unique(candidates), target, case_sensitive)
  if file then
    return { status = "resolved", file = file }
  end
  local ambiguous = unique(candidates)
  if #ambiguous > 1 then
    return { status = "ambiguous", candidates = ambiguous }
  end
  return { status = "unresolved", target = target }
end

return M
