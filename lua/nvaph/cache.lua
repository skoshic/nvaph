local util = require("nvaph.util")

local M = {}

local function cache_dir()
  local path = vim.fn.stdpath("cache") .. "/nvaph"
  util.mkdir(path)
  return path
end

function M.path(root)
  return cache_dir() .. "/" .. vim.fn.sha256(root) .. ".json"
end

function M.load(root)
  local path = M.path(root)
  local content = util.read(path)
  if not content then
    return nil
  end
  local ok, data = pcall(vim.json.decode, content)
  if not ok or type(data) ~= "table" then
    return nil
  end
  return data
end

function M.save(root, data)
  data.saved_at = os.time()
  local ok, content = pcall(vim.json.encode, data)
  if not ok then
    return false
  end
  return util.write(M.path(root), content) == true
end

function M.clear(root)
  os.remove(M.path(root))
end

return M
