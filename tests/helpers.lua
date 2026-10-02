local M = {}

function M.temp_project(files)
  local root = vim.fn.tempname()
  vim.fn.mkdir(root, "p")
  for path, content in pairs(files) do
    local full = root .. "/" .. path
    vim.fn.mkdir(vim.fs.dirname(full), "p")
    local file = assert(io.open(full, "wb"))
    file:write(content)
    file:close()
  end
  return root
end

function M.remove(path)
  vim.fn.delete(path, "rf")
end

return M
