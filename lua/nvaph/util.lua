local M = {}

function M.normalize(path)
  if not path or path == "" then
    return ""
  end
  local normalized = vim.fs.normalize(path):gsub("\\", "/")
  local ok, real = pcall(vim.uv.fs_realpath, normalized)
  if ok and real then
    local resolved = vim.fs.normalize(real):gsub("\\", "/")
    return resolved
  end
  return normalized
end

function M.join(...)
  return vim.fs.joinpath(...)
end

function M.relative(path, root)
  path = M.normalize(path)
  root = M.normalize(root)
  if path == root then
    return "."
  end
  local prefix = root .. "/"
  if path:sub(1, #prefix) == prefix then
    return path:sub(#prefix + 1)
  end
  return path
end

function M.is_within(path, root)
  path = M.normalize(path)
  root = M.normalize(root)
  return path == root or path:sub(1, #root + 1) == root .. "/"
end

function M.extension(path)
  return path:match("(%.[^./]+)$") or ""
end

function M.stem(path)
  local base = vim.fs.basename(path)
  return (base:gsub("%.[^.]+$", ""))
end

function M.read(path)
  local file, err = io.open(path, "rb")
  if not file then
    return nil, err
  end
  local content = file:read("*a")
  file:close()
  return content
end

function M.write(path, content)
  local file, err = io.open(path, "wb")
  if not file then
    return nil, err
  end
  file:write(content)
  file:close()
  return true
end

function M.mkdir(path)
  return vim.fn.mkdir(path, "p")
end

function M.notify(message, level)
  vim.notify("nvaph: " .. message, level or vim.log.levels.INFO)
end

function M.schedule(fn)
  if vim.in_fast_event() then
    vim.schedule(fn)
  else
    fn()
  end
end

function M.hash(text)
  local value = 2166136261
  for index = 1, #text do
    value = (value * 16777619 + text:byte(index)) % 4294967296
  end
  return value
end

function M.hash01(text)
  return (M.hash(text) % 1000003) / 1000003
end

function M.uniq(list)
  local seen = {}
  local out = {}
  for _, value in ipairs(list) do
    if not seen[value] then
      seen[value] = true
      out[#out + 1] = value
    end
  end
  return out
end

function M.trim(value)
  return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

function M.display_width(value)
  return vim.fn.strdisplaywidth(value)
end

return M
