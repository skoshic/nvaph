local util = require("nvaph.util")

local M = {}

local function ignored(name, patterns)
  for _, pattern in ipairs(patterns) do
    if name == pattern or name:sub(1, #pattern + 1) == pattern .. "/" then
      return true
    end
  end
  return false
end

local function walk(dir, root, opts, out)
  if opts.max_files and #out >= opts.max_files then
    return
  end
  local entries = {}
  for name, kind in vim.fs.dir(dir) do
    entries[#entries + 1] = { name = name, kind = kind }
  end
  table.sort(entries, function(left, right)
    return left.name < right.name
  end)
  for _, entry in ipairs(entries) do
    if not ignored(entry.name, opts.ignore) then
      local path = util.join(dir, entry.name)
      if entry.kind == "directory" then
        if not opts.shallow then
          walk(path, root, opts, out)
        end
      elseif entry.kind == "file" then
        local stat = vim.uv.fs_stat(path)
        if stat then
          local extension = util.extension(path):lower()
          local allowed = not opts.extensions or vim.tbl_contains(opts.extensions, extension)
          if allowed then
            out[#out + 1] = {
              abs = path,
              rel = util.relative(path, root),
              extension = extension,
              mtime = stat.mtime and stat.mtime.sec or 0,
              size = stat.size or 0,
            }
          end
        end
      end
    end
  end
end

function M.scan(root, opts)
  opts = opts or {}
  opts.ignore = opts.ignore or {}
  opts.max_files = opts.max_files or 20000
  local out = {}
  if vim.fn.isdirectory(root) == 0 then
    return out
  end
  walk(root, root, opts, out)
  return out
end

return M
