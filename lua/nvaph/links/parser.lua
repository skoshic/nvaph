local M = {}

local function fence(line)
  local run = line:match("^%s*(`+)") or line:match("^%s*(~+)")
  if run and #run >= 3 then
    return run
  end
  return nil
end

local function mask_inline_code(line)
  local chars = {}
  for index = 1, #line do
    chars[index] = line:sub(index, index)
  end
  local index = 1
  while index <= #line do
    if line:sub(index, index) == "`" or line:sub(index, index) == "~" then
      local marker = line:sub(index, index)
      local length = 1
      while line:sub(index + length, index + length) == marker do
        length = length + 1
      end
      local close_at = line:find(string.rep(marker, length), index + length, true)
      if close_at and length <= 3 then
        for position = index, close_at + length - 2 do
          chars[position] = " "
        end
        index = close_at + length - 1
      else
        index = index + length
      end
    else
      index = index + 1
    end
  end
  return table.concat(chars)
end

local function split_link(value)
  local target, alias = value:match("^([^|]*)|(.*)$")
  if not target then
    target = value
    alias = nil
  end
  target = target:gsub("^%s+", ""):gsub("%s+$", "")
  local hash = target:find("#", 1, true)
  local path
  local fragment
  if hash then
    path = target:sub(1, hash - 1)
    fragment = target:sub(hash + 1)
  else
    path = target
    fragment = ""
  end
  path = path:gsub("^%s+", ""):gsub("%s+$", "")
  fragment = fragment:gsub("^%s+", ""):gsub("%s+$", "")
  return path, fragment, alias
end

local function clean_markdown_target(value)
  value = value:gsub("^%s*<", ""):gsub(">%s*$", "")
  value = value:gsub("^%s+", ""):gsub("%s+$", "")
  return value:match("^([^%s]+)") or value
end

local function is_external(value)
  return value:match("^[%a][%w+.-]*://") ~= nil or value:match("^mailto:") ~= nil
end

function M.parse(text)
  local links = {}
  local lines = vim.split(text or "", "\n", { plain = true })
  local in_fence
  for row, line in ipairs(lines) do
    local marker = fence(line)
    if in_fence then
      if marker and #marker >= #in_fence then
        in_fence = nil
      end
    elseif marker then
      in_fence = marker
    else
      local masked = mask_inline_code(line)
      local position = 1
      while true do
        local start_at, end_at, inner = masked:find("%[%[(.-)%]%]", position)
        if not start_at then
          break
        end
        local path, fragment, alias = split_link(inner)
        links[#links + 1] = {
          kind = line:sub(start_at - 1, start_at - 1) == "!" and "embed" or "wiki",
          raw = line:sub(start_at, end_at),
          target = path,
          fragment = fragment,
          alias = alias,
          row = row,
          start_col = start_at - 1,
          end_col = end_at,
          external = is_external(path),
        }
        position = end_at + 1
      end
      position = 1
      while true do
        local start_at, end_at, label, destination = masked:find("%[([^%]]*)%]%(([^%)]*)%)", position)
        if not start_at then
          break
        end
        local target = clean_markdown_target(destination)
        local hash = target:find("#", 1, true)
        local path = target
        local fragment = ""
        if hash then
          path = target:sub(1, hash - 1)
          fragment = target:sub(hash + 1)
        end
        links[#links + 1] = {
          kind = "markdown",
          raw = line:sub(start_at, end_at),
          target = path,
          fragment = fragment,
          alias = label,
          row = row,
          start_col = start_at - 1,
          end_col = end_at,
          external = is_external(target),
        }
        position = end_at + 1
      end
    end
  end
  table.sort(links, function(left, right)
    if left.row == right.row then
      return left.start_col < right.start_col
    end
    return left.row < right.row
  end)
  return links
end

return M
